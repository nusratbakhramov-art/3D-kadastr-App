/// Tikish natijasi va qamrovni PIKSELDAN o'lchash.
///
/// `panorama` loyihasidagi `lib/services/panorama_stitcher.dart` dan
/// ko'chirilgan sof qism. [selectBand] ataylab OpenCV'siz va qurilmasiz
/// yuradigan qilib saqlangan — manbada xato aynan shu yerda yashagan.
library;

import 'package:flutter/foundation.dart';

/// Tikish urinishidan nima qaytdi.
sealed class StitchOutcome {
  const StitchOutcome();
}

class StitchSuccess extends StitchOutcome {
  const StitchSuccess({
    required this.path,
    required this.width,
    required this.height,
    required this.verticalCoverDeg,
    this.diagnostics = const <String, Object?>{},
  });

  final String path;
  final int width;
  final int height;

  /// Yo'lda o'lchangan raqamlar (`report.json` uchun). FAQAT primitivlar —
  /// bu isolate chegarasidan o'tadi.
  final Map<String, Object?> diagnostics;

  /// Panorama 180° qutbdan-qutbgacha oraliqning qanchasini qamraydi.
  ///
  /// PIKSELDAN o'lchanadi, nisbatdan chiqarilmaydi. Eski
  /// `height * 360 / width` XATO edi va aynan zarar keltiradigan
  /// yo'nalishda xato edi: u O'RASH TO'RTBURCHAGINI o'qiydi, tuval esa
  /// kadrlar birlashmasidan tashqaridagi hamma joyni qora qoldiradi.
  ///
  /// Bu ikki yo'l bilan tishlaydi:
  ///
  ///  * Bir nechta qator bo'lsa birlashma to'rtburchak emas, BOCHKA —
  ///    gorizontda eng keng, yuqori va pastda torayadi — ya'ni to'rtburchak
  ///    har doim piksel bor qismidan baland;
  ///  * yomon ro'yxatga olingan bitta kadr o'ta chetki pitch'ga tushadi,
  ///    u yerda sferik o'rash chegarasiz kattalashtiradi va to'rtburchakni
  ///    haqiqatdan uzoqqa cho'zadi.
  ///
  /// 42 kadrli 0/+30/-30 halqasi 123.8° haqiqiy qamrov berdi, to'rtburchak
  /// esa 125.6 dedi; haqiqiy qo'l capture'ida o'sha halqa 4096×2048
  /// to'rtburchak chiqardi va eski formula buni TO'LIQ 180° sfera deb
  /// o'qidi. Farq — ko'ruvchi keyin qutblarga o'rab qo'ygan qoraning o'zi.
  final double verticalCoverDeg;
}

class StitchFailure extends StitchOutcome {
  const StitchFailure(
    this.message, {
    this.needsMoreImages = false,
    this.diagnostics = const <String, Object?>{},
  });

  final String message;

  /// Yiqilishdan oldin o'lchangan hamma narsa. Halqa yopilmagan holatda bu
  /// eng yaxshi qator haqiqatan qancha qamraganini olib keladi — ya'ni
  /// capture yaqin qolganini yoki umuman uzoq bo'lganini aytadigan raqam.
  final Map<String, Object?> diagnostics;

  /// Ustma-ustlik yetmadi. Foydalanuvchiga «ichki xato» emas, «sekinroq
  /// burilib qayta suratga ol» deyilishi kerak.
  final bool needsMoreImages;
}

/// Tuvaldagi qatorlar oynasi.
@immutable
class Band {
  const Band(this.top, this.height);

  final int top;
  final int height;
}

/// Qamrov skani nima topdi — band bor yoki yo'q.
///
/// O'lchovlar IKKI holatda ham qaytadi: yiqilishdan keyin ular capture
/// qanchalik yaqin kelganining yagona dalili, va «eng yaxshi qator 43%
/// qamragan» bilan «eng yaxshi qator 99% qamragan, lekin markazdan
/// siljigan» butunlay boshqa nosozlik hisoboti.
@immutable
class BandScan {
  const BandScan({
    required this.band,
    required this.bestRow,
    required this.bestFraction,
    required this.usedFraction,
    required this.rows,
  });

  final Band? band;

  /// Eng ko'p qamralgan qator indeksi — O'LCHANGAN gorizont.
  final int bestRow;

  /// O'sha qatorning qanchasida tasvir bor, 0..1.
  final double bestFraction;

  /// Band narvonning qaysi pog'onasida qabul qilingani; qabul qilinmasa
  /// `null`.
  final double? usedFraction;

  final int rows;

  Map<String, Object?> toJson() => <String, Object?>{
    'panoRows': rows,
    'bestRow': bestRow,
    'bestRowCoverage': double.parse(bestFraction.toStringAsFixed(4)),
    'acceptedAtFraction': usedFraction,
    if (band != null) 'bandTop': band!.top,
    if (band != null) 'bandHeight': band!.height,
  };
}

/// Gorizontni o'rab turgan, 360° bo'ylab qamralgan eng baland qatorlar
/// to'plami.
///
/// [rowSums] har qatorda `255 * (qamralgan piksel)` ni saqlaydi, [cols] esa
/// panorama eni — ya'ni to'liq qamralgan qator `cols * 255` beradi.
///
/// Band tasvirning vertikal MARKAZIDAN emas, O'LCHANGAN gorizontdan — eng
/// ko'p qamralgan qatordan — o'stiriladi. Aynan shu farq «halqa yopilmadi»
/// degan asossiz xatoni butunlay tuzatadi.
///
/// `rows ~/ 2` dan boshlash gorizont o'rash to'rtburchagining markazida
/// turadi deb hisoblardi. U yerda turmaydi, sababi
/// [StitchSuccess.verticalCoverDeg] da yozilgan: tuval kadrlar
/// birlashmasidan tashqarini qora qoldiradi, sferik o'rash esa qutbga
/// yaqinlashganda chegarasiz kattalashtiradi. `CaptureRing.defaultRows` dagi
/// zenit va nadir qatorlari aynan ±90 da turadi, ya'ni foydalanuvchi
/// ilovaning o'z taklifini qabul qilib qutblarni olishi bilanoq o'sha
/// kadrlar to'rtburchakni gorizont bandidan uzoqqa cho'zadi va markaziy
/// qatorni qora bo'shliqqa surib yuboradi. Keyin narvonning har pog'onasi
/// hech qachon piksel bo'lmagan qatorda yiqilardi va mukammal 42 kadrli
/// halqa «bir joyda turib to'liq 360° aylan» degan — foydalanuvchi
/// allaqachon bajargan — maslahat bilan rad etilardi.
///
/// Maksimumni olish qator yig'indilari ustidan bitta o'tishga arziydi va
/// markazdan siljigan to'rtburchak bilan aldab bo'lmaydi: qaysi qatorda eng
/// ko'p piksel bo'lsa, o'rash uni qayerga qo'ygan bo'lsa ham, gorizont
/// o'sha.
///
/// Eng yaxshi qatorda ham HAQIQIY teshik bo'lsa band `null` bo'ladi — bu
/// esa burilish yopilmaganini bildiradi va u holda burchak bo'yicha
/// hech qanday tayanch qolmaydi, chunki enni 360° ga bog'lash bu quvurdagi
/// yagona masshtab.
///
/// Qamrov SANALADI, minimum bilan tekshirilmaydi: qator 99.5%ida piksel
/// bo'lsa o'tadi. Har bitta pikselni talab qilish aylanadagi bitta qorong'i
/// eshikka butun qatorni veto qilish huquqini berardi, haqiqiy interyer esa
/// shundaylarga to'la. Bu funksiya ushlash uchun yaratilgan qora
/// tirqishlar qatorning 0.5% iga hech qachon o'xshamaydi.
BandScan selectBand(List<int> rowSums, int cols) {
  final int rows = rowSums.length;
  final int full = cols * 255;

  int bestRow = 0;
  int bestSum = -1;
  for (int y = 0; y < rows; y++) {
    if (rowSums[y] > bestSum) {
      bestSum = rowSums[y];
      bestRow = y;
    }
  }
  final double bestFraction = (full == 0 || rows == 0) ? 0 : bestSum / full;

  // Rad etish emas, YUMSHATISH. 0.995 — ideal (teshigi deyarli yo'q qator),
  // lekin gorizont yonida bitta zaif chogi bor capture undan o'tmaydi va
  // 97% tayyor panorama uchun xato qaytarish hech kimga yordam bermaydi.
  // Narvondan band topilguncha yuriladi; bo'shroq band faqat chetlarda bir
  // nechta qora piksel bo'lishi mumkinligini bildiradi — butun capture'ni
  // yo'qotish yonida bu ko'rinmaydi.
  for (final double fraction in <double>[0.995, 0.97, 0.90, 0.80]) {
    final int needed = (full * fraction).round();
    if (bestSum < needed) continue;

    int top = bestRow;
    int bottom = bestRow;
    while (top - 1 >= 0 && rowSums[top - 1] >= needed) {
      top--;
    }
    while (bottom + 1 < rows && rowSums[bottom + 1] >= needed) {
      bottom++;
    }
    return BandScan(
      band: Band(top, bottom - top + 1),
      bestRow: bestRow,
      bestFraction: bestFraction,
      usedFraction: fraction,
      rows: rows,
    );
  }
  return BandScan(
    band: null,
    bestRow: bestRow,
    bestFraction: bestFraction,
    usedFraction: null,
    rows: rows,
  );
}
