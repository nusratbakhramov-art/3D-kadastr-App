/// Raster yadrolari — OpenCV o'rnini bosadigan sof Dart amallari.
///
/// `panorama` loyihasidagi `sensor_stitcher.dart` da 509 ta `cv.*` chaqiruvi
/// bor, lekin ular atigi OLTI xil ish qiladi. Shu fayl ulardan raster
/// qismini beradi: `remap`, `resize` (AREA/LINEAR/NEAREST), `pyrDown`,
/// `pyrUp`, element-wise arifmetika va `CV_8U` ga aylantirish.
///
/// ⚠️ BIT-BIR XILLIK KUTILMAYDI. OpenCV bilinear'ni 5 bitli fixed-point'da
/// hisoblaydi, biz float'da; `cvRound` juft tomonga yaxlitlaydi, Dart'ning
/// `.round()` esa noldan uzoqqa. Farq bir darajaning ichida qoladi va ko'z
/// bilan ko'rinmaydi. Solishtirish PIKSEL-PIKSEL emas, ko'rinish va
/// `flatSeamVisibility` bilan qilinadi.
///
/// ⚠️ Lekin quyidagi farqlar JIM va HALOKATLI — ular kompilyatsiya xatosi
/// bermaydi, faqat natijani buzadi. Har biri shu fayldagi bitta qarorga
/// aylangan va test bilan bog'langan:
///
/// | OpenCV xatti-harakati | Bu yerda |
/// |---|---|
/// | `remap` sukut chegarasi `BORDER_CONSTANT` (0) | [remapBilinear] ning `border` sukuti 0 — tuvalda qoplanmagan joy QORA qoladi va maska shuni o'qiydi |
/// | `INTER_AREA` kasr koeffitsiyentda chegara pikseliga QISMIY og'irlik beradi | [resizeArea] qismiy og'irlikni hisoblaydi; oddiy box o'rtacha ≠ |
/// | `INTER_NEAREST` indeksi `floor(dst·src/dstSize)`, YAXLITLASH emas | [nearestIndexMap] |
/// | `pyrDown` yadrosi `[1,4,6,4,1]/16`, chegara `BORDER_REFLECT_101` | [kPyrKernel], [reflect101] |
/// | `convertTo(CV_8U)` saturate + ROUND qiladi | [saturateCastU8] — `.toInt()` (kesish) panoramani bir daraja qoraytiradi |
/// | `0/0` OpenCV'da 0, Dart'da NaN | [divideSafe] maxrajga 1e-6 qo'shadi; busiz bitta qoplanmagan piksel butun bandni NaN qiladi |
/// | `compare(CMP_GT)` QAT'IY `>` | [compareGt] — `>=` qilinsa teng og'irlikda oxirgi kadr yutadi va butun label xaritasi, chok va blend boshqacha bo'ladi |
///
/// Hamma yadro BIR KANALLI (planar) ishlaydi. Bu ataylab: ko'p kanalli
/// interleaved buferda har piksel uchun uch marta indeks hisoblanadi va
/// kesh yomon ishlaydi. Rangli kadr uch marta chaqiriladi.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// `pyrDown`/`pyrUp` yadrosi — OpenCV bilan bir xil.
///
/// Yadro yoki chegarani o'zgartirish feather kengligini o'zgartiradi, ya'ni
/// manbadagi `9378c62` sozlagan narsani buzadi (maska piramidasi l=0,1,2 da
/// qattiq, l=3,4,5 da yumshoq).
const List<double> kPyrKernel = <double>[
  1 / 16,
  4 / 16,
  6 / 16,
  4 / 16,
  1 / 16,
];

/// `BORDER_REFLECT_101` — chegara pikselini TAKRORLAMASDAN aks ettiradi:
/// `gfedcb|abcdefgh|gfedcba`.
///
/// `BORDER_REFLECT` (takrorlaydigan) bilan aralashtirish chegarada yarim
/// piksel siljish beradi — panorama chetlarida ko'rinadigan chiziq.
int reflect101(int i, int n) {
  if (n == 1) return 0;
  final int period = 2 * n - 2;
  int k = i % period;
  if (k < 0) k += period;
  return k < n ? k : period - k;
}

int _clamp(int i, int n) => i < 0 ? 0 : (i >= n ? n - 1 : i);

/// `saturate_cast<uchar>` — YAXLITLAYDI va 0..255 ga qisadi.
///
/// `.toInt()` kesib tashlaydi, ya'ni har piksel o'rtacha yarim darajaga
/// pastga tushadi va butun panorama sezilarli qorayadi.
int saturateCastU8(double v) {
  if (v.isNaN) return 0;
  final int r = v.round();
  return r < 0 ? 0 : (r > 255 ? 255 : r);
}

/// Float planni `CV_8U` ga aylantirish, ixtiyoriy `alpha`/`beta` bilan
/// (OpenCV `convertTo` kabi: `dst = saturate(src * alpha + beta)`).
Uint8List toU8(Float32List src, {double alpha = 1, double beta = 0}) {
  final out = Uint8List(src.length);
  for (int i = 0; i < src.length; i++) {
    out[i] = saturateCastU8(src[i] * alpha + beta);
  }
  return out;
}

Float32List toF32(Uint8List src, {double alpha = 1, double beta = 0}) {
  final out = Float32List(src.length);
  for (int i = 0; i < src.length; i++) {
    out[i] = src[i] * alpha + beta;
  }
  return out;
}

// ── Namuna olish ────────────────────────────────────────────────────────────

/// Bilinear namuna. Manba tashqarisi [border] (sukut 0 — `BORDER_CONSTANT`).
///
/// [replicate] berilsa chegara pikseli cho'ziladi (`BORDER_REPLICATE`).
double sampleBilinear(
  Float32List src,
  int w,
  int h,
  double x,
  double y, {
  double border = 0,
  bool replicate = false,
}) {
  if (!replicate && (x < -1 || y < -1 || x > w || y > h)) return border;
  final int x0 = x.floor();
  final int y0 = y.floor();
  final double fx = x - x0;
  final double fy = y - y0;

  double at(int px, int py) {
    if (replicate) return src[_clamp(py, h) * w + _clamp(px, w)];
    if (px < 0 || py < 0 || px >= w || py >= h) return border;
    return src[py * w + px];
  }

  final double v00 = at(x0, y0);
  final double v10 = at(x0 + 1, y0);
  final double v01 = at(x0, y0 + 1);
  final double v11 = at(x0 + 1, y0 + 1);
  return v00 * (1 - fx) * (1 - fy) +
      v10 * fx * (1 - fy) +
      v01 * (1 - fx) * fy +
      v11 * fx * fy;
}

/// `cv.remap(src, mapX, mapY, INTER_LINEAR)`.
///
/// [mapX]/[mapY] — har DST pikseli uchun SRC koordinatasi. Bu teskari
/// xaritalash: har chiqish pikseli qayerdan olinishini aytadi, ya'ni
/// chiqishda teshik qolmaydi (to'g'ri xaritalash qoldiradi).
Float32List remapBilinear(
  Float32List src,
  int sw,
  int sh,
  Float32List mapX,
  Float32List mapY,
  int dw,
  int dh, {
  double border = 0,
  bool replicate = false,
}) {
  assert(mapX.length == dw * dh && mapY.length == dw * dh);
  final out = Float32List(dw * dh);
  for (int i = 0; i < out.length; i++) {
    out[i] = sampleBilinear(
      src,
      sw,
      sh,
      mapX[i],
      mapY[i],
      border: border,
      replicate: replicate,
    );
  }
  return out;
}

// ── resize ──────────────────────────────────────────────────────────────────

/// `INTER_NEAREST` indeks xaritasi: `floor(dst · src / dstSize)`.
///
/// YAXLITLASH EMAS. Yaxlitlansa label chegarasi yarim piksel siljiydi va
/// chok DP boshqa yo'l tanlaydi — natija boshqacha bo'ladi, lekin hech
/// qanday xato chiqmaydi.
Int32List nearestIndexMap(int sw, int sh, int dw, int dh) {
  final xs = Int32List(dw);
  for (int dx = 0; dx < dw; dx++) {
    xs[dx] = math.min((dx * sw / dw).floor(), sw - 1);
  }
  final out = Int32List(dw * dh);
  for (int dy = 0; dy < dh; dy++) {
    final int sy = math.min((dy * sh / dh).floor(), sh - 1);
    final int rowBase = sy * sw;
    final int dstBase = dy * dw;
    for (int dx = 0; dx < dw; dx++) {
      out[dstBase + dx] = rowBase + xs[dx];
    }
  }
  return out;
}

/// `cv.resize(..., INTER_NEAREST)`.
Float32List resizeNearest(Float32List src, int sw, int sh, int dw, int dh) {
  final map = nearestIndexMap(sw, sh, dw, dh);
  final out = Float32List(map.length);
  for (int i = 0; i < map.length; i++) {
    out[i] = src[map[i]];
  }
  return out;
}

/// Label xaritalari uchun — o'sha indeks qoidasi, butun sonlar ustida.
///
/// Label'ni float sifatida masshtablash MUMKIN EMAS: interpolatsiya
/// bo'lmasa ham float ↔ int aylanishida ikki qo'shni label orasida
/// mavjud bo'lmagan uchinchi qiymat paydo bo'lishi mumkin.
Int32List resizeNearestLabels(Int32List src, int sw, int sh, int dw, int dh) {
  final map = nearestIndexMap(sw, sh, dw, dh);
  final out = Int32List(map.length);
  for (int i = 0; i < map.length; i++) {
    out[i] = src[map[i]];
  }
  return out;
}

/// Bir o'lchov bo'ylab `INTER_AREA` og'irliklari.
///
/// Har dst pikseli `[dx·s, (dx+1)·s)` oralig'ini qamraydi va chegaradagi
/// src pikseli QISMIY og'irlik oladi. Oddiy box o'rtacha (butun piksellarni
/// teng olish) kasr koeffitsiyentda boshqa natija beradi.
({Int32List starts, Int32List counts, Float64List weights}) _areaWeights(
  int srcSize,
  int dstSize,
) {
  final double s = srcSize / dstSize;
  final starts = Int32List(dstSize);
  final counts = Int32List(dstSize);
  final w = <double>[];
  for (int d = 0; d < dstSize; d++) {
    final double lo = d * s;
    final double hi = math.min((d + 1) * s, srcSize.toDouble());
    final int i0 = lo.floor();
    final int i1 = (hi - 1e-12).floor();
    starts[d] = i0;
    counts[d] = i1 - i0 + 1;
    for (int i = i0; i <= i1; i++) {
      final double a = math.max(lo, i.toDouble());
      final double b = math.min(hi, i + 1.0);
      w.add(math.max(0.0, b - a) / (hi - lo));
    }
  }
  return (starts: starts, counts: counts, weights: Float64List.fromList(w));
}

/// `cv.resize(..., INTER_AREA)` — FAQAT kichraytirish uchun.
///
/// OpenCV `INTER_AREA` ni kattalashtirishda `INTER_NEAREST` ga o'xshash
/// ishlatadi, bizda esa u kerak emas (quvurda faqat kichraytirish bor).
/// Shuning uchun bu holat ochiq rad etiladi — jimgina boshqa natija
/// berishdan ko'ra.
Float32List resizeArea(Float32List src, int sw, int sh, int dw, int dh) {
  assert(
    dw <= sw && dh <= sh,
    'INTER_AREA faqat kichraytirish uchun ($sw×$sh → $dw×$dh)',
  );
  final xw = _areaWeights(sw, dw);
  final yw = _areaWeights(sh, dh);

  // Gorizontal o'tish: sh × dw.
  final mid = Float32List(sh * dw);
  for (int y = 0; y < sh; y++) {
    final int sBase = y * sw;
    final int mBase = y * dw;
    int k = 0;
    for (int dx = 0; dx < dw; dx++) {
      double acc = 0;
      final int i0 = xw.starts[dx];
      final int n = xw.counts[dx];
      for (int i = 0; i < n; i++) {
        acc += src[sBase + i0 + i] * xw.weights[k + i];
      }
      k += n;
      mid[mBase + dx] = acc;
    }
  }

  // Vertikal o'tish: dh × dw.
  final out = Float32List(dh * dw);
  int k = 0;
  for (int dy = 0; dy < dh; dy++) {
    final int j0 = yw.starts[dy];
    final int n = yw.counts[dy];
    final int oBase = dy * dw;
    for (int dx = 0; dx < dw; dx++) {
      double acc = 0;
      for (int j = 0; j < n; j++) {
        acc += mid[(j0 + j) * dw + dx] * yw.weights[k + j];
      }
      out[oBase + dx] = acc;
    }
    k += n;
  }
  return out;
}

/// `cv.resize(..., INTER_LINEAR)` — OpenCV'ning YARIM PIKSEL markazi
/// kelishuvi bilan: `fx = (dx + 0.5)·s - 0.5`.
///
/// `dx·s` (markazsiz) ishlatilsa butun tasvir yarim piksel siljiydi. Bir
/// o'tishda ko'rinmaydi, piramida oktavalari bo'ylab yig'ilib ketadi.
Float32List resizeLinear(Float32List src, int sw, int sh, int dw, int dh) {
  final double sx = sw / dw;
  final double sy = sh / dh;
  final out = Float32List(dw * dh);
  for (int dy = 0; dy < dh; dy++) {
    final double fy = (dy + 0.5) * sy - 0.5;
    final int y0 = fy.floor();
    final double wy = fy - y0;
    final int y0c = _clamp(y0, sh);
    final int y1c = _clamp(y0 + 1, sh);
    final int oBase = dy * dw;
    for (int dx = 0; dx < dw; dx++) {
      final double fx = (dx + 0.5) * sx - 0.5;
      final int x0 = fx.floor();
      final double wx = fx - x0;
      final int x0c = _clamp(x0, sw);
      final int x1c = _clamp(x0 + 1, sw);
      final double v0 =
          src[y0c * sw + x0c] * (1 - wx) + src[y0c * sw + x1c] * wx;
      final double v1 =
          src[y1c * sw + x0c] * (1 - wx) + src[y1c * sw + x1c] * wx;
      out[oBase + dx] = v0 * (1 - wy) + v1 * wy;
    }
  }
  return out;
}

// ── Piramida ────────────────────────────────────────────────────────────────

/// `cv.pyrDown` — `[1,4,6,4,1]/16` bilan silliqlab, keyin har ikkinchi
/// pikselni olish. `BORDER_REFLECT_101`.
///
/// [dw]/[dh] berilmasa `(sw+1)~/2` olinadi (OpenCV sukuti). Berilsa u
/// sukutdan eng ko'p 1 ga farq qilishi mumkin — OpenCV ham shuni talab
/// qiladi. Bu quvurda kerak: akkumulyator o'lchamlari aniq berilgan
/// bo'lishi shart, aks holda oktavalar bir-biriga to'g'ri kelmaydi.
Float32List pyrDown(Float32List src, int sw, int sh, {int? dw, int? dh}) {
  final int ow = dw ?? ((sw + 1) >> 1);
  final int oh = dh ?? ((sh + 1) >> 1);
  assert(
    (ow - ((sw + 1) >> 1)).abs() <= 1 && (oh - ((sh + 1) >> 1)).abs() <= 1,
    'pyrDown o‘lchami sukutdan 1 dan ko‘p farq qilmasligi kerak',
  );

  // Gorizontal silliqlash + gorizontal decimatsiya: sh × ow.
  final mid = Float32List(sh * ow);
  for (int y = 0; y < sh; y++) {
    final int sBase = y * sw;
    final int mBase = y * ow;
    for (int x = 0; x < ow; x++) {
      final int cx = 2 * x;
      double acc = 0;
      for (int t = -2; t <= 2; t++) {
        acc += kPyrKernel[t + 2] * src[sBase + reflect101(cx + t, sw)];
      }
      mid[mBase + x] = acc;
    }
  }

  // Vertikal silliqlash + vertikal decimatsiya: oh × ow.
  final out = Float32List(oh * ow);
  for (int y = 0; y < oh; y++) {
    final int cy = 2 * y;
    final int oBase = y * ow;
    for (int t = -2; t <= 2; t++) {
      final double k = kPyrKernel[t + 2];
      final int rBase = reflect101(cy + t, sh) * ow;
      for (int x = 0; x < ow; x++) {
        out[oBase + x] += k * mid[rBase + x];
      }
    }
  }
  return out;
}

/// `cv.pyrUp` — nollar bilan kattalashtirib, o'sha yadro bilan (×4)
/// silliqlash.
///
/// ×4 koeffitsiyenti energiyani saqlash uchun: nollar kiritilgach yadro
/// og'irligining faqat chorak qismi haqiqiy pikselga tushadi. Ikki o'tishning
/// har birida ×2 qo'llanadi.
///
/// ⚠️ CHEGARA. Aks ettirish MANBA indeksiga qo'llanadi (nollar kiritilgan
/// panjara indeksiga emas). Bu OpenCV'dan eng chetki ustun/qatorda bir
/// piksel farq qilishi mumkin — bu yerda OpenCV'siz tekshirib bo'lmadi.
/// Amalda muhim emas, chunki piramida tahlili ham, sintezi ham AYNAN shu
/// operatorni ishlatadi, ya'ni `pyrDown`/`pyrUp` juftligi o'z-o'ziga
/// mos qoladi va Laplas qayta tiklashda xato bekor bo'ladi. Buni
/// `raster_test.dart` dagi «tekis plan chetida ham o'zgarmaydi» va
/// «Laplas qayta tiklash» testlari qotiradi.
Float32List pyrUp(Float32List src, int sw, int sh, {int? dw, int? dh}) {
  final int ow = dw ?? sw * 2;
  final int oh = dh ?? sh * 2;

  // Gorizontal: sh × ow.
  final mid = Float32List(sh * ow);
  for (int y = 0; y < sh; y++) {
    final int sBase = y * sw;
    final int mBase = y * ow;
    for (int x = 0; x < ow; x++) {
      double acc = 0;
      for (int t = -2; t <= 2; t++) {
        final int gx = x + t;
        if (gx.isOdd) continue;
        acc += kPyrKernel[t + 2] * src[sBase + reflect101(gx >> 1, sw)];
      }
      mid[mBase + x] = 2 * acc;
    }
  }

  // Vertikal: oh × ow.
  final out = Float32List(oh * ow);
  for (int y = 0; y < oh; y++) {
    final int oBase = y * ow;
    for (int t = -2; t <= 2; t++) {
      final int gy = y + t;
      if (gy.isOdd) continue;
      final double k = 2 * kPyrKernel[t + 2];
      final int rBase = reflect101(gy >> 1, sh) * ow;
      for (int x = 0; x < ow; x++) {
        out[oBase + x] += k * mid[rBase + x];
      }
    }
  }
  return out;
}

// ── Element-wise ────────────────────────────────────────────────────────────

Float32List add(Float32List a, Float32List b) => _zip(a, b, (x, y) => x + y);
Float32List subtract(Float32List a, Float32List b) =>
    _zip(a, b, (x, y) => x - y);
Float32List multiply(Float32List a, Float32List b) =>
    _zip(a, b, (x, y) => x * y);
Float32List absDiff(Float32List a, Float32List b) =>
    _zip(a, b, (x, y) => (x - y).abs());
Float32List maxOf(Float32List a, Float32List b) =>
    _zip(a, b, (x, y) => math.max(x, y));

/// `_safeDivide` — maxrajga `1e-6` qo'shadi.
///
/// OpenCV `0/0` uchun 0 qaytaradi, Dart esa NaN. NaN keyingi hamma amalga
/// yuqadi, ya'ni tuvalning QOPLANMAGAN bitta pikseli butun bandni NaN
/// qilib qo'yadi va panorama qora chiqadi.
Float32List divideSafe(Float32List num, Float32List den, {double eps = 1e-6}) =>
    _zip(num, den, (x, y) => x / (y + eps));

/// `cv.compare(a, b, CMP_GT)` — QAT'IY `>`, natija 255 yoki 0.
///
/// `>=` qilinsa teng og'irlikda ikkinchi kadr yutadi va butun label
/// xaritasi, chok yo'nalishi va blend boshqacha bo'ladi.
Uint8List compareGt(Float32List a, Float32List b) {
  assert(a.length == b.length);
  final out = Uint8List(a.length);
  for (int i = 0; i < a.length; i++) {
    out[i] = a[i] > b[i] ? 255 : 0;
  }
  return out;
}

/// `cv.threshold(..., THRESH_BINARY)` — `> thresh` bo'lsa [maxVal].
Uint8List threshold(Float32List src, double thresh, {int maxVal = 255}) {
  final out = Uint8List(src.length);
  for (int i = 0; i < src.length; i++) {
    out[i] = src[i] > thresh ? maxVal : 0;
  }
  return out;
}

int countNonZero(Uint8List src) {
  int n = 0;
  for (int i = 0; i < src.length; i++) {
    if (src[i] != 0) n++;
  }
  return n;
}

Float32List _zip(
  Float32List a,
  Float32List b,
  double Function(double, double) f,
) {
  assert(a.length == b.length, 'o‘lchamlar mos emas: ${a.length} vs ${b.length}');
  final out = Float32List(a.length);
  for (int i = 0; i < a.length; i++) {
    out[i] = f(a[i], b[i]);
  }
  return out;
}
