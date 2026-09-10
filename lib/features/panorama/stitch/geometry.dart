/// Ekvirektangulyar tuval geometriyasi — kadr tuvalning QAYSI qismiga
/// tushishi.
///
/// Bu fayl proyektorning (12-qadam) ichki tsikli bilan BIR XIL kelishuvni
/// ishlatishi shart. Proyektor tezlik uchun arifmetikani o'z ichiga yozadi,
/// shu sababli kelishuv shu yerda bir marta e'lon qilinadi va
/// `geometry_test.dart` ikkalasini bog'laydi:
///
///     lat = π/2 − (v + 0.5)/canvasH · π
///     lon = (u + 0.5)/canvasW · 2π
///     d   = (cos lat · sin lon,  sin lat,  cos lat · cos lon)
///
/// Yarim piksel (`+ 0.5`) — piksel MARKAZI. Uni tashlab ketish butun
/// panoramani yarim piksel siljitadi; bitta o'tishda ko'rinmaydi, lekin
/// kadr izini hisoblash bilan proyeksiya orasida nomuvofiqlik bo'lsa
/// izning chetidagi qator umuman hisoblanmay qoladi.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Kadrning tuvaldagi izi — YOZILMAGAN (wrap qilinmagan) ustun
/// koordinatalarida.
///
/// [u0] MANFIY bo'lishi mumkin va `u0 + width` tuval enidan OSHISHI mumkin:
/// chokka qaragan kadr uni kesib o'tadi va shu yerda qisib qo'yish kadrni
/// jimgina yarmiga bo'lardi. O'rash bir marta, yozish paytida,
/// [columnBlocks] bilan hal qilinadi.
class Roi {
  const Roi(this.u0, this.v0, this.width, this.height);

  final int u0;
  final int v0;
  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  String toString() => 'Roi(u0: $u0, v0: $v0, $width×$height)';
}

/// Tuval qatori → kenglik (radian). Qator 0 — ZENIT.
double latOfRow(int v, int canvasH) =>
    math.pi / 2 - (v + 0.5) / canvasH * math.pi;

/// Tuval ustuni → uzunlik (radian), 0..2π.
double lonOfCol(int u, int canvasW) => (u + 0.5) / canvasW * 2 * math.pi;

/// Kenglik → tuval qatori (kasr). [latOfRow] ning teskarisi.
double rowOfLat(double lat, int canvasH) =>
    (math.pi / 2 - lat) / math.pi * canvasH - 0.5;

/// Uzunlik → tuval ustuni (kasr). [lonOfCol] ning teskarisi.
double colOfLon(double lon, int canvasW) =>
    lon / (2 * math.pi) * canvasW - 0.5;

/// Sferadagi yo'nalish birlik vektori.
///
/// ⚠️ O'q tartibi ATAYLAB shunday: Y — VERTIKAL (yuqoriga), Z — oldinga,
/// X — o'ngga. `cameraRayFromPixel` va rotatsiya matritsasi aynan shu
/// tizimda yozilgan; X va Z ni almashtirish 90° burilish beradi va hech
/// qanday xato chiqarmaydi.
Float64List directionOf(double lat, double lon) {
  final double cosLat = math.cos(lat);
  final v = Float64List(3);
  v[0] = cosLat * math.sin(lon);
  v[1] = math.sin(lat);
  v[2] = cosLat * math.cos(lon);
  return v;
}

/// Rotatsiya matritsasidan kadr MARKAZI qayerga qaraganini oladi.
///
/// Matritsa ustun-tartibda (`rotationMatrix` qaytargani kabi): kameraning
/// oldinga qaragan o'qi (+Z) dunyoda `(r[2], r[5], r[8])` ga tushadi.
/// Shu sababli `lon = atan2(r[2], r[8])` va `lat = asin(r[5])`.
///
/// `asin` argumenti QISILADI: suzuvchi nuqta xatosi `r[5]` ni 1.0000001
/// qilib qo'yishi mumkin va `asin` NaN qaytaradi — keyin butun iz NaN
/// bo'ladi va kadr tuvalga umuman tushmaydi.
({double lon, double lat}) frameCentre(List<double> r) => (
  lon: math.atan2(r[2], r[8]),
  lat: math.asin(r[5].clamp(-1.0, 1.0)),
);

/// Kadr ko'rish burchagining YARIM diagonali, radian, kichik zaxira bilan.
///
/// Kadr sferada shu radiusli qalpoqni qamraydi. Zaxira (`+0.02` rad ≈ 1.15°)
/// yaxlitlash va sensor xatosi uchun: iz kadrdan bir oz KATTA bo'lsa faqat
/// bir necha ortiqcha piksel hisoblanadi, KICHIK bo'lsa esa kadr cheti
/// qirqiladi va chokda qora chiziq qoladi.
double capRadius(int fw, int fh, double focal, {double marginRad = 0.02}) {
  final double diag = math.sqrt(fw * fw + fh * fh) / 2;
  return math.atan(diag / focal) + marginRad;
}

/// Kadr tuvalda QAYERGA tushishi mumkin.
///
/// NEGA IZ KERAK. Har kadr uchun butun tuvalni aylanish 3072×1536 da 4.7 M
/// piksel × 76 kadr ≈ 360 M trigonometrik hisob bo'lardi. Qalpoqni
/// chegaralab, faqat shu piksellarni hisoblash butun yondashuvni
/// bajarilishi mumkin qiladi.
Roi footprint({
  required double lon,
  required double lat,
  required int fw,
  required int fh,
  required double focal,
  required int canvasW,
  required int canvasH,
  double marginRad = 0.02,
}) {
  final double radius = capRadius(fw, fh, focal, marginRad: marginRad);

  final double latMax = math.min(math.pi / 2, lat + radius);
  final double latMin = math.max(-math.pi / 2, lat - radius);

  final int v0 = ((math.pi / 2 - latMax) / math.pi * canvasH)
      .floor()
      .clamp(0, canvasH - 1);
  final int v1 = ((math.pi / 2 - latMin) / math.pi * canvasH)
      .ceil()
      .clamp(0, canvasH - 1);

  // Qutb yaqinida qalpoq butun aylanani o'rab oladi va chegaralaydigan
  // uzunlik umuman qolmaydi.
  //
  // ⚠️ Bu tez yo'l `s >= 1` tekshiruviga MATEMATIK EKVIVALENT:
  // `|lat| + radius >= π/2  ⟺  sin(radius) >= cos(lat)  ⟺  s >= 1`.
  // O'lchandi — 67.3° FOV da −90°..+90° oralig'ida 1801 kenglikning
  // BIRORTASIDA ham ikki shart farq qilmadi. Ya'ni u qutb kadrlarini
  // qutqarayotgani ROST EMAS; `else` shoxi ularni o'zi ham to'g'ri
  // hisoblaydi (`cosLat ≈ 6e-17` da `s ≈ 1e16 >= 1`).
  //
  // Shart FAQAT bitta degenerat holatda ish beradi: `radius == 0` va
  // `lat == ±90°`, ya'ni nol ko'rish burchagi. U holda `s = 0/0⁺ = 0` va
  // `else` shoxi `halfLon = 0` berardi — nol enli iz. Tez yo'l esa
  // xavfsiz ortiqcha baho (`π`) beradi. Shu sababli SAQLANADI: narxi
  // bitta solishtirish, foydasi — nol enli iz hech qachon chiqmaydi.
  // Bundan tashqari `cosLat <= 1e-6` 1e16 kabi oraliq qiymatni umuman
  // hisoblamaslikka imkon beradi.
  final double cosLat = math.cos(lat);
  double halfLon;
  if (lat.abs() + radius >= math.pi / 2 || cosLat <= 1e-6) {
    halfLon = math.pi;
  } else {
    final double s = math.sin(radius) / cosLat;
    halfLon = s >= 1 ? math.pi : math.asin(s);
  }

  final double uc = lon / (2 * math.pi) * canvasW;
  final double halfU = halfLon / (2 * math.pi) * canvasW + 1;
  final int u0 = (uc - halfU).floor();
  final int u1 = (uc + halfU).ceil();

  // En tuvaldan OSHMAYDI: bu [columnBlocks] ning ikkitadan ko'p blok
  // qaytarmasligini kafolatlaydi.
  final int w = math.min(canvasW, u1 - u0 + 1);
  return Roi(u0, v0, w, v1 - v0 + 1);
}

/// O'ralmagan izni tuval ustun bloklariga bo'ladi — ENG KO'PI IKKITA.
///
/// Har blok `(srcX, dstX, run)`: izning `srcX` ustunidan boshlab `run` ta
/// ustun tuvalning `dstX` ustuniga yoziladi.
///
/// Uzunlik davriyligi FAQAT shu yerda hal qilinadi. Kadrni oldinroq qisib
/// qo'yish (`u0.clamp(0, canvasW)`) chokka qaragan kadrni yarmiga bo'lardi
/// va u yerda doimiy vertikal chiziq qolardi.
List<(int srcX, int dstX, int run)> columnBlocks(Roi roi, int canvasW) {
  // ⚠️ Bu SHART, tekshiruv emas. Iz eni tuvaldan oshsa tsikl baribir ikki
  // blok qaytaradi — lekin ular BIR XIL ustunlarga tushadi va ikkinchisi
  // birinchisini qayta yozadi. Ya'ni nosozlik «uch blok» bo'lib emas,
  // jimgina qayta yozish bo'lib ko'rinadi. `footprint` enni aynan shu
  // sababli `min(canvasW, ...)` bilan qisadi.
  assert(
    roi.width <= canvasW,
    'iz eni tuvaldan oshdi (${roi.width} > $canvasW) — '
    '`footprint` uni qisishi kerak edi',
  );
  final blocks = <(int, int, int)>[];
  int done = 0;
  while (done < roi.width) {
    // ⚠️ Dart'ning `%` si musbat bo'luvchi uchun HAR DOIM manfiy bo'lmagan
    // natija beradi (`(-10) % 3072 == 3062`) — C/Java'dan farqli. Manbada
    // `((x % w) + w) % w` yozilgan edi; bu C-izm va Dart'da keraksiz.
    // `.remainder()` esa C uslubidagi variant va u bu yerda BUZADI —
    // shuning uchun tanlov `geometry_test.dart` da qotirilgan.
    final int u = (roi.u0 + done) % canvasW;
    final int run = math.min(roi.width - done, canvasW - u);
    if (run <= 0) break;
    blocks.add((done, u, run));
    done += run;
  }
  return blocks;
}
