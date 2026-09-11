/// Kadrni KULRANG tuvalga warp qilish — ekspozitsiya tenglashtiruvchisi
/// (14-qadam) va chok yo'naltiruvchisi (15-qadam) UCHUN.
///
/// NEGA ALOHIDA FAYL. Ikkala iste'molchi ham ayni bir narsani so'raydi:
/// «kadr i tuvalning qayerini, qanday yorqinlik bilan qoplaydi». Farq
/// faqat MASSHTABDA va gain'da:
///
/// | Iste'molchi | Tuval | Gain |
/// |---|---|---|
/// | `pairwiseBrightness` (14) | 256×128 | 1 — gain hali yechilmagan |
/// | chok DP (15) | [seamDivFor] tanlagani | yechilgan gain |
///
/// Shu sababli bu yerda masshtab ham, gain ham PARAMETR — funksiya
/// ikkalasiga bir xil xizmat qiladi.
///
/// ⚠️ Bu ASOSIY proyeksiya emas va undan ATAYLAB farq qiladi:
/// o'rtachalab qo'yiladi (`winnerTakeAll: false`) va og'irlik tekis
/// (`blendPower: 1`). Sabab: bu yerda «qaysi kadr yutdi» degan savol
/// yo'q — bitta kadrning o'z hissasi kerak, ya'ni yutuvchini tanlash
/// ma'nosiz, tor og'irlik esa kadr chetini sun'iy qoraytirardi va ham
/// gain o'rtachasini, ham chok narxini buzardi.
library;

import 'dart:typed_data';

import '../math/rotation.dart';
import 'project.dart';
import 'raw_plane.dart';

/// Kulrang kadrlar JAMI shundan oshmasligi kerak.
///
/// Chok yo'naltiruvchisi HAMMA kadrni bir vaqtda ushlab turadi — DP
/// juftlarni ixtiyoriy tartibda oladi va uch pass yuradi, ya'ni kadrni
/// «kerak bo'lganda qayta warp qilaman» deyish har passda butun
/// proyeksiyani qaytadan bajarish degani.
///
/// 150 MB manbadan olingan. 3072 tuval va 76 kadrda `div = 2` chiqadi:
/// `76 × 1536 × 768 = 85.5 MB` — byudjetga sig'adi.
const int kGrayBudgetBytes = 150 * 1024 * 1024;

/// O'lchov tuvali asosiy tuvaldan kamida ikki barobar kichik.
///
/// `1` (ya'ni to'liq tuval) UMUMAN ro'yxatda yo'q: chok past chastotali
/// qaror, to'liq rezolyutsiya unga hech narsa qo'shmaydi, xotirasi esa
/// to'rt barobar.
const int kGrayDivMin = 2;
const int kGrayDivMax = 5;

/// [kGrayBudgetBytes] ga sig'adigan eng YIRIK o'lchov masshtabi.
///
/// Yirikroq masshtab chokni aniqroq yo'naltiradi, shuning uchun eng
/// kichik `div` dan boshlab qidiriladi va birinchi sig'gani olinadi.
int grayDivFor(int frames, int canvasW) {
  for (int d = kGrayDivMin; d <= kGrayDivMax; d++) {
    final int w = canvasW ~/ d;
    if (frames * w * (w ~/ 2) <= kGrayBudgetBytes) return d;
  }
  return kGrayDivMax;
}

/// Kulrang warp uchun kadr qanchaga kichraytiriladi.
///
/// Manbadagi `max(320, canvasW · 0.25)`. O'lchov tuvali allaqachon
/// kichik, kadrni undan katta ushlab turish bekor ish: har piksel
/// baribir bir necha marta namuna olinadi.
int grayFrameWidth(int canvasW) {
  final int quarter = (canvasW * 0.25).round();
  return quarter < 320 ? 320 : quarter;
}

/// Qoplanganlik chegarasi — `cover` shundan past piksel QOPLANMAGAN.
///
/// Manbadagi `threshold(cover, 0.5, 1, THRESH_BINARY)`. Yarim — chunki
/// `cover` bilinear namunadan keladi va kadr chetida kasr qiymat
/// beradi; 0 dan katta bo'lishini talab qilish izni bir piksel
/// kengaytirardi, ya'ni qoplanmagan joy qoplangan ko'rinardi.
const double kGrayCoverThreshold = 0.5;

// OpenCV `cvtColor(..., BGR2GRAY)` ning 8-bitli qat'iy nuqta
// koeffitsiyentlari. Float 0.299/0.587/0.114 emas, AYNAN shular:
// natija bir darajaga farq qilsa chok DP boshqa yo'l tanlashi mumkin,
// va manbadagi 0.78 ko'rsatkichi bilan solishtirib bo'lmay qolardi.
const int _r2y = 4899;
const int _g2y = 9617;
const int _b2y = 1868;
const int _yuvShift = 14;

/// Kadrni kulrang ekvirektangulyar tuvalga qo'yadi.
///
/// Qaytadi: `canvasW × canvasH` uzunlikdagi plan, unda
///
/// * **`0` — piksel bu kadr bilan QOPLANMAGAN**;
/// * `1..255` — haqiqiy yorqinlik.
///
/// ⚠️ SHU SHARTNOMA butun chok DP sining asosi: u `ga[p] == 0` ni
/// «bu kadr bu yerda yo'q» deb o'qiydi. Shu sababli haqiqiy piksel
/// hech qachon 0 bo'lmaydi — u avval 1 gacha KO'TARILADI, keyin
/// tashqarisi 0 ga qaytariladi. Qora shift yoki qorong'i burchak
/// HAQIQIY o'lchov, uni «kadr bu yerga yetmagan» bilan adashtirish
/// DP ga o'sha joydan kesib o'tishni bepul ko'rsatardi.
Uint8List warpGray({
  required RawPlane frame,
  required List<double> rotation,
  required double longSideFovDeg,
  required int canvasW,
  required int canvasH,
  double gain = 1,
}) {
  assert(canvasW > 0 && canvasH > 0);
  assert(frame.channels == 1 || frame.channels == 3);

  final out = Uint8List(canvasW * canvasH);

  final double focal = focalPx(frame.width, frame.height, longSideFovDeg);
  final FrameMap map = buildFrameMap(
    rotation: rotation,
    frameW: frame.width,
    frameH: frame.height,
    focal: focal,
    canvasW: canvasW,
    canvasH: canvasH,
    // ⚠️ CHIZIQLI og'irlik, `blendPower: 1`. Bu ikkisi BIRGA yuradi:
    // `taperWeight` darajaga faqat `winnerTakeAll: false` da ko'taradi,
    // ya'ni bittasini unutish ikkinchisini jimgina kuchsizlantiradi.
    //
    // NEGA 16 EMAS. Tuvalda bitta kadr bor, ya'ni og'irlik
    // `color / weight` da QISQARISHI kerak va tanlangan daraja natijaga
    // ta'sir qilmasligi lozim. Lekin bo'linish `weight + 1e-6` bilan
    // (NaN qo'riqchisi), va `t¹⁶` kadr chetida o'sha epsilondan kichik
    // bo'lib qoladi — o'shanda piksel o'z yorqinligini emas, epsilon
    // nisbatini oladi. O'lchandi: `blendPower: 16` da 422 qoplangan
    // pikseldan 346 tasi qorayadi, eng pasti 200 dan 2 ga tushadi.
    // Chok DP si buni «bu yerda qorong'i, kesib o'tish arzon» deb
    // o'qirdi — aynan kadr chetida, ya'ni chok o'tadigan joyda.
    blendPower: 1,
    winnerTakeAll: false,
  );
  if (map.roi.isEmpty) return out;

  final canvas = PanoCanvas(
    width: canvasW,
    height: canvasH,
    channels: frame.channels,
    // Label bu yerda ma'nosiz: tuvalda bitta kadr bor.
    withLabel: false,
  );
  compositeFrame(
    canvas,
    map,
    <Uint8List>[for (int c = 0; c < frame.channels; c++) frame.plane(c)],
    frame.width,
    frame.height,
    0,
    gain: gain,
    winnerTakeAll: false,
  );

  final int pixels = canvasW * canvasH;
  final bool mono = frame.channels == 1;

  for (int i = 0; i < pixels; i++) {
    if (canvas.cover[i] < kGrayCoverThreshold) continue;

    // ⚠️ TARTIB MUHIM: avval har KANAL 8-bitga yaxlitlanadi, keyin
    // yorqinlik hisoblanadi. Manbada shunday (`convertTo(CV_8UC3)` →
    // `cvtColor`), va teskarisi boshqa natija beradi — kanal
    // yaxlitlanishi yorqinlikka nochiziqli o'tadi.
    final double w = canvas.weight[i] + 1e-6;
    int y;
    if (mono) {
      y = _u8(canvas.color[i] / w);
    } else {
      // `plane(0)` — R, `plane(2)` — B (`RawPlane` RGB saqlaydi), ya'ni
      // koeffitsiyentlar shu tartibda qo'llanadi. Manba BGR ustida
      // ishlaydi — kanallarni almashtirib yuborish yorqinlikni
      // qizil/ko'k sahnalarda sezilarli siljitardi.
      final int r = _u8(canvas.color[i] / w);
      final int g = _u8(canvas.color[pixels + i] / w);
      final int b = _u8(canvas.color[2 * pixels + i] / w);
      y = (r * _r2y + g * _g2y + b * _b2y + (1 << (_yuvShift - 1))) >>
          _yuvShift;
    }

    // Nolni faqat «qoplanmagan» uchun qoldiramiz.
    out[i] = y < 1 ? 1 : (y > 255 ? 255 : y);
  }

  return out;
}

/// `saturate_cast<uchar>` — [saturateCastU8] bilan bir xil, lekin
/// `Uint8List` ga yozilmaydi.
int _u8(double v) {
  if (v.isNaN) return 0;
  final int r = v.round();
  return r < 0 ? 0 : (r > 255 ? 255 : r);
}
