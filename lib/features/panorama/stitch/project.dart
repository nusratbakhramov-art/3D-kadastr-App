/// Proyeksiya — kadrni ekvirektangulyar tuvalga qo'yish.
///
/// Quvurning yuragi. Har chiqish pikseli uchun TESKARI xaritalash ishlatiladi
/// (piksel → yo'nalish → kadr pikseli), chunki to'g'ri xaritalash chiqishda
/// teshik qoldiradi.
///
/// ## Ikki rejim
///
/// **`winnerTakeAll` (asosiy yo'l).** Har piksel uchun BITTA kadr yutadi —
/// og'irligi eng katta bo'lgani. Og'irlik LINEAR qoldiriladi: darajaga
/// ko'tarish monoton, ya'ni argmax'ni o'zgartirmaydi, lekin masshtabni
/// buzadi.
///
/// **O'rtachalash rejimi.** Og'irlik `t^blendPower` bo'ladi va rang
/// `sum/weight` sifatida hisoblanadi. Kulrang tuval (nozik moslashtirish
/// uchun) shu rejimda yasaladi.
///
/// ## NEGA O'RTACHALASH ASOSIY YO'L EMAS
///
/// Sensor burchaklari bir-ikki darajaga aniq, ya'ni har chiqish pikselini
/// ko'radigan uch-to'rt kadr bir necha piksel farq bilan kelishmaydi.
/// Yumshoq og'irlik shu nomuvofiqlikni O'RTACHALAYDI va natija hamma
/// kadrning bir vaqtdagi xiralashuvi bo'ladi. Tik og'irlik esa markazi eng
/// yaqin kadrni to'liq yutdiradi — o'sha kadrning O'Z o'tkirligi saqlanadi
/// va murosa faqat choklar bo'ylab tor tasmada qoladi.
///
/// ## KO'CHIRILMAGAN NARSALAR
///
/// `seamPenalty` (chok nomuvofiqlik jarimasi), `deform` (kadrning
/// egilishi) va `routeSeams` manbada BOR, lekin `f85cacd` da O'CHIRILGAN:
/// «ular o'lchagan narsa noto'g'ri edi va ilova ko'rsatadigan
/// masshtabda panoramani ochiqdan-ochiq buzadi». Sukut qiymatlari
/// `seamPenalty = 0`, `deform = false`, `routeSeams = false`. O'chirilgan
/// kodni ko'chirish faqat ishlatilmaydigan yo'l va u bilan birga
/// keladigan `gaussianBlur` yadrosini olib kelardi — shuning uchun
/// KO'CHIRILMADI. Kerak bo'lsa manbada saqlanib turibdi.
///
/// `k1` (linza buzilishi) ham ko'chirilmadi — sababi
/// `rotation.dart` dagi `cameraRayFromPixel` izohida.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'raster.dart';

/// Qoplangan, lekin og'irligi nolga teng piksel uchun eng kichik og'irlik.
///
/// NEGA KERAK. Kadr chekkasida tor (`t = 0`) og'irlik nolga tushadi. Yutuvchi
/// QAT'IY `>` bilan tanlanadi, ya'ni og'irligi nol bo'lgan piksel HECH KIM
/// tomonidan olinmaydi va qora qolib ketadi. Bu ikki kadr uchinchisi
/// ustidan tushmasdan tutashgan joyda bir piksel enli chiziq bo'lib
/// chiqadi, keyin detal o'tishi o'sha qora piksellarni panoramaga QORA
/// SOCH TOLASI bo'lib ko'taradi — manbada 20 mingga yaqin, 224 darajaga
/// chuqur. Ular «yamoq» deb atalgan va birinchi versiyadan beri
/// ko'rinardi.
const double kCoveredFloor = 1e-8;

/// Kadr pikselining tor og'irligi — markazda 1, chetda 0.
///
/// Ajratilgani sababi: [buildFrameMap] ning ichida bu shox amalda
/// tekshirib bo'lmaydigan bo'lib qoladi (piksel kadr chekkasiga AYNAN
/// tushishini talab qiladi), bu yerda esa to'g'ridan-to'g'ri sinaladi.
///
/// [kCoveredFloor] poli AYNAN shu holat uchun: `x == 0` da `wx = 0`,
/// ya'ni og'irlik nol. Yutuvchi QAT'IY `>` bilan tanlanadi, demak nol
/// og'irlikli piksel HECH KIM tomonidan olinmaydi va qora qoladi — keyin
/// detal o'tishi uni QORA SOCH TOLASI bo'lib panoramaga ko'taradi.
double taperWeight(
  double x,
  double y,
  double cx,
  double cy, {
  int blendPower = 16,
  bool winnerTakeAll = true,
}) {
  final double wx = 1 - (x - cx).abs() / cx;
  final double wy = 1 - (y - cy).abs() / cy;
  // `wx` va `wy` ikkalasi ham [0, 1] da (piksel kadr ichida), ya'ni `t`
  // manfiy BO'LMAYDI — u faqat aynan chekkada nolga teng bo'ladi.
  double t = wx * wy;
  if (!winnerTakeAll) {
    // Tik og'irlik. `winnerTakeAll` da LINEAR qoldiriladi — darajaga
    // ko'tarish argmax'ni o'zgartirmaydi, lekin masshtabni buzadi.
    for (int e = 1; e < blendPower; e <<= 1) {
      t *= t;
    }
  }
  return t < kCoveredFloor ? kCoveredFloor : t;
}

/// Kadrning tuvaldagi xaritasi — TASVIRDAN MUSTAQIL.
///
/// Ajratilgani sababi: bu qism sof geometriya va uni tasvirsiz, telefonsiz
/// tekshirish mumkin. Xarita tayyor bo'lgach kompozit shunchaki namuna
/// olish va solishtirishdan iborat.
class FrameMap {
  const FrameMap({
    required this.roi,
    required this.mapX,
    required this.mapY,
    required this.weight,
    required this.valid,
  });

  final Roi roi;

  /// Har ROI pikseli uchun KADR koordinatasi. `-1` = namuna yo'q.
  final Float32List mapX;
  final Float32List mapY;

  /// Tor og'irlik. `0` = qoplanmagan.
  final Float32List weight;

  /// `1` = qoplangan, `0` = yo'q. Qamrovni o'lchash uchun (`selectBand`)
  /// og'irlikdan ALOHIDA kerak: og'irlik `kCoveredFloor` ga tushishi
  /// mumkin, lekin piksel baribir qoplangan.
  final Float32List valid;

  int get length => roi.width * roi.height;
}

/// Kadr uchun xarita va og'irlik hisoblaydi.
///
/// [rotation] — 3×3, `rotationMatrix` qaytargan tartibda. Faqat uning
/// TRANSPOZI ishlatiladi: dunyodagi yo'nalishni kamera fazosiga qaytarish.
FrameMap buildFrameMap({
  required List<double> rotation,
  required int frameW,
  required int frameH,
  required double focal,
  required int canvasW,
  required int canvasH,
  int blendPower = 16,
  bool winnerTakeAll = true,
}) {
  final double cx = frameW / 2;
  final double cy = frameH / 2;
  final List<double> r = rotation;

  final centre = frameCentre(r);
  final Roi roi = footprint(
    lon: centre.lon,
    lat: centre.lat,
    fw: frameW,
    fh: frameH,
    focal: focal,
    canvasW: canvasW,
    canvasH: canvasH,
  );

  final int n = roi.width * roi.height;
  final mapX = Float32List(n)..fillRange(0, n, -1);
  final mapY = Float32List(n)..fillRange(0, n, -1);
  final weight = Float32List(n);
  final valid = Float32List(n);
  if (n == 0) {
    return FrameMap(
      roi: roi,
      mapX: mapX,
      mapY: mapY,
      weight: weight,
      valid: valid,
    );
  }

  for (int j = 0; j < roi.height; j++) {
    final double lat = latOfRow(roi.v0 + j, canvasH);
    final double cosLat = math.cos(lat);
    final double sinLat = math.sin(lat);
    final int row = j * roi.width;

    for (int i = 0; i < roi.width; i++) {
      // ⚠️ O'RALMAGAN ustun. `roi.u0` manfiy bo'lishi mumkin va
      // `lonOfCol` uni 2π dan tashqariga chiqaradi — bu TO'G'RI, sinus
      // va kosinus davriy. O'rash faqat YOZISHDA kerak.
      final double lon = lonOfCol(roi.u0 + i, canvasW);

      final double dx = cosLat * math.sin(lon);
      final double dy = sinLat;
      final double dz = cosLat * math.cos(lon);

      // Transpoz: dunyo → kamera.
      final double cz = r[2] * dx + r[5] * dy + r[8] * dz;
      final int k = row + i;
      // Linza orqasida yoki uning tekisligida — namuna yo'q.
      //
      // ⚠️ Bu tekshiruv bizning FOV'imizda (67.3°) HECH QACHON
      // ishlamaydi va bu o'lchangan: iz — markaz atrofidagi ~38.5°
      // qalpoqning lat/lon to'rtburchagi, uning eng uzoq burchagi ham
      // markazdan 90° dan yaqin, ya'ni `cz` musbat qoladi. Kadr
      // chegarasi tekshiruvi qolganini o'zi ushlaydi.
      //
      // Shunga qaramay SAQLANADI: juda keng FOV'da (fishye, ~170°)
      // radius 90° ga yaqinlashadi, iz butun sferani egallaydi va
      // kameraning ORQASIDAGI yo'nalishlar izga tushadi. Kesilmasa
      // ular kadrni sferaning teskari tomoniga «arvoh» bo'lib
      // qo'yardi. `project_test.dart` shuni keng FOV bilan sinaydi.
      if (cz <= 1e-6) continue;

      final double nx = (r[0] * dx + r[3] * dy + r[6] * dz) / cz;
      final double ny = (r[1] * dx + r[4] * dy + r[7] * dz) / cz;
      // IKKALA MINUS ham ataylab — `cameraRayFromPixel` izohiga qara.
      final double x = cx - focal * nx;
      final double y = cy - focal * ny;
      if (x < 0 || y < 0 || x > frameW - 1 || y > frameH - 1) continue;

      mapX[k] = x;
      mapY[k] = y;
      valid[k] = 1;

      weight[k] = taperWeight(
        x,
        y,
        cx,
        cy,
        blendPower: blendPower,
        winnerTakeAll: winnerTakeAll,
      );
    }
  }

  return FrameMap(
    roi: roi,
    mapX: mapX,
    mapY: mapY,
    weight: weight,
    valid: valid,
  );
}

/// Akkumulyator tuval.
///
/// Rang PLANAR saqlanadi (`RRR…GGG…BBB…`) — raster qatlami bilan bir xil
/// kelishuv.
class PanoCanvas {
  PanoCanvas({
    required this.width,
    required this.height,
    this.channels = 3,
    this.withLabel = true,
  }) : color = Float32List(width * height * channels),
       weight = Float32List(width * height),
       cover = Float32List(width * height),
       label = withLabel ? (Int32List(width * height)..fillRange(0, width * height, -1)) : null;

  final int width;
  final int height;
  final int channels;
  final bool withLabel;

  /// `winnerTakeAll` da — YUTUVCHI rang. O'rtachalashda — rang×og'irlik
  /// yig'indisi.
  final Float32List color;

  /// `winnerTakeAll` da — yutuvchining og'irligi. O'rtachalashda —
  /// og'irliklar yig'indisi.
  final Float32List weight;

  /// Qoplanganlik yig'indisi. Og'irlikdan ALOHIDA — qamrovni o'lchash
  /// uchun.
  final Float32List cover;

  /// Qaysi kadr yutgani. `-1` = hech kim. Multi-band blend TOZA label
  /// xaritasiga tayanadi.
  final Int32List? label;

  int get pixels => width * height;
}

/// Kadrni tuvalga qo'yadi.
///
/// [planes] — kadr kanallari, planar. [frameIndex] label xaritasiga
/// tushadi.
///
/// [rowFrom]/[rowTo] — tuval QATORLARI oynasi (`rowTo` kirmaydi). Isolate
/// parallelligi shu bilan ishlaydi: har ishchi o'z qatorlar tasmasiga
/// EGALIK qiladi, ya'ni bir xil pikselga ikki ishchi yozmaydi va qulf
/// kerak emas.
void compositeFrame(
  PanoCanvas canvas,
  FrameMap map,
  List<Uint8List> planes,
  int frameW,
  int frameH,
  int frameIndex, {
  double gain = 1,
  bool winnerTakeAll = true,
  int rowFrom = 0,
  int? rowTo,
}) {
  assert(planes.length == canvas.channels);
  final int hi = rowTo ?? canvas.height;
  final Roi roi = map.roi;
  if (roi.isEmpty) return;

  // Kadr kanallarini bir marta float'ga o'giramiz — `remapBilinear` shu
  // turda ishlaydi. Bir kanal 701×1246 ≈ 3.5 MB, uch kanal 10.5 MB —
  // o'tkinchi va bitta kadr uchun.
  final warped = <Float32List>[
    for (final p in planes)
      remapBilinear(
        toF32(p),
        frameW,
        frameH,
        map.mapX,
        map.mapY,
        roi.width,
        roi.height,
      ),
  ];

  for (final (srcX, dstX, run) in columnBlocks(roi, canvas.width)) {
    for (int j = 0; j < roi.height; j++) {
      final int v = roi.v0 + j;
      if (v < rowFrom || v >= hi) continue;
      final int srcRow = j * roi.width + srcX;
      final int dstRow = v * canvas.width + dstX;

      for (int i = 0; i < run; i++) {
        final int s = srcRow + i;
        if (map.valid[s] == 0) continue;
        final int d = dstRow + i;

        canvas.cover[d] += map.valid[s];
        final double w = map.weight[s];

        if (winnerTakeAll) {
          // ⚠️ QAT'IY `>`. `>=` bo'lsa teng og'irlikda OXIRGI kadr
          // yutadi, ya'ni yutuvchi kadrlarning kelish TARTIBIGA bog'liq
          // bo'lib qoladi va butun label xaritasi, chok va blend
          // boshqacha chiqadi.
          if (w > canvas.weight[d]) {
            canvas.weight[d] = w;
            for (int c = 0; c < canvas.channels; c++) {
              canvas.color[c * canvas.pixels + d] = warped[c][s] * gain;
            }
            canvas.label?[d] = frameIndex;
          }
        } else {
          canvas.weight[d] += w;
          for (int c = 0; c < canvas.channels; c++) {
            canvas.color[c * canvas.pixels + d] += warped[c][s] * gain * w;
          }
        }
      }
    }
  }
}

/// Yakuniy rang — planar `Uint8List`.
///
/// `winnerTakeAll` da rang allaqachon yutuvchining o'zi, shunchaki
/// `CV_8U` ga tushiriladi. O'rtachalashda `sum / weight` — va bo'linish
/// [divideSafe] bilan, chunki qoplanmagan pikselda `0/0` NaN berardi va
/// NaN keyingi hamma amalga yuqadi.
Uint8List resolveCanvas(PanoCanvas c, {bool winnerTakeAll = true}) {
  if (winnerTakeAll) return toU8(c.color);
  final out = Uint8List(c.color.length);
  for (int ch = 0; ch < c.channels; ch++) {
    final int base = ch * c.pixels;
    for (int i = 0; i < c.pixels; i++) {
      out[base + i] = saturateCastU8(
        c.color[base + i] / (c.weight[i] + 1e-6),
      );
    }
  }
  return out;
}

/// `selectBand` o'qiydigan birliklarda har qatorning qamrovi.
///
/// `255 · (qamralgan piksel)`. `cover` ishlatiladi, `weight` EMAS:
/// og'irlik [kCoveredFloor] ga tushishi mumkin, lekin piksel baribir
/// qoplangan.
List<int> rowCoverage(PanoCanvas c) => <int>[
  for (int y = 0; y < c.height; y++)
    () {
      int n = 0;
      final int base = y * c.width;
      for (int x = 0; x < c.width; x++) {
        if (c.cover[base + x] > 0) n++;
      }
      return n * 255;
    }(),
];

// ── Isolate bo'laklari ──────────────────────────────────────────────────────

/// Tuvalni GORIZONTAL tasmalarga bo'ladi.
///
/// NEGA GORIZONTAL. Tasmalar tuval qatorlari bo'yicha kesiladi, ya'ni har
/// ishchining chiqish pikselllari boshqalar bilan KESISHMAYDI va qulf
/// kerak emas. Vertikal bo'lish bunday ishlamaydi: chokka qaragan kadr
/// tuvalning ikki chetiga ham yozadi (`columnBlocks`), ya'ni ustun
/// tasmalari kadrni bo'lib tashlamaydi va bir ustunga ikki ishchi
/// yozishi mumkin.
///
/// Tasmalar bir-biriga TENG bo'lmaydi: qoldiq birinchi tasmalarga
/// tarqatiladi, ya'ni eng katta va eng kichik tasma farqi bitta qator.
List<(int v0, int rows)> horizontalSlices(int canvasH, int workers) {
  assert(canvasH > 0 && workers > 0);
  final int n = math.min(workers, canvasH);
  final int base = canvasH ~/ n;
  final int extra = canvasH % n;
  final out = <(int, int)>[];
  int v = 0;
  for (int i = 0; i < n; i++) {
    final int rows = base + (i < extra ? 1 : 0);
    out.add((v, rows));
    v += rows;
  }
  assert(v == canvasH, 'tasmalar tuvalni to‘liq qoplamadi');
  return out;
}

/// Kadr izi shu qatorlar tasmasiga tushadimi.
///
/// Ishchi o'z tasmasiga tegmaydigan kadrlar ustidan umuman ishlamasligi
/// kerak: gorizont kadri 1536 qatorli tuvalning atigi 658 qatorini
/// qamraydi, ya'ni to'rtta ishchidan ikkitasi uni butunlay o'tkazib
/// yuboradi.
bool roiIntersectsRows(Roi roi, int v0, int rows) =>
    !roi.isEmpty && roi.v0 < v0 + rows && v0 < roi.v0 + roi.height;
