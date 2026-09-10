/// Ekspozitsiya tenglashtirish — har kadr uchun yorug'lik koeffitsiyenti.
///
/// MUAMMO. Telefon har kadrni ALOHIDA o'lchaydi. Deraza tomonga qaragan
/// kadr va devor tomonga qaragan kadr chokda uchrashganda yorug'lik
/// SAKRAYDI. Xonaning bo'sh devorida — ko'z chalg'iydigan detal ham,
/// geometriyani aniqlaydigan feature ham yo'q joyda — aynan o'sha
/// yorug'lik pog'onasi CHOKNING O'ZI bo'ladi. Boshqa hech narsa uni
/// belgilamaydi.
///
/// ⚠️ NEGA MEDIANAGA TORTISH ISHLAMAYDI. Oldingi yondashuv har kadrni
/// to'plamning median yorqinligiga masshtablardi. Bu gistogrammani
/// markazlashtiradi, lekin KO'RINADIGAN narsaga — ikki qo'shni kadr
/// orasidagi farqga — hech narsa qilmaydi. Ikki kadr ikkalasi ham
/// medianadan bir xil uzoqlikda, lekin QARAMA-QARSHI tomonda bo'lishi
/// mumkin va chok o'sha joyda qoladi.
///
/// YECHIM (Brown va Lowe ning gain kompensatsiyasi). Koeffitsiyentlar
/// tayinlanmaydi, YECHILADI: ustma-ust tushgan har juft kadr uchun
/// ULARNING UMUMIY sohasida o'lchangan o'rtacha yorqinlik masshtabdan
/// keyin TENG chiqishi kerak. n kadr uchun bu n noma'lumli eng kichik
/// kvadratlar masalasi; differensiallash har kadrga bitta chiziqli
/// tenglama beradi va Gauss-Seidel bir necha o'nlab o'tishda yaqinlashadi.
///
/// Geometrik moslashtirishdan farqli, buni BO'SH DEVOR ALDAY OLMAYDI: u
/// yorqinlikni solishtiradi, bo'sh devorning yorqinligi esa mukammal
/// aniqlangan.
library;

import 'dart:math' as math;

/// Yechim natijasi va uning diagnostikasi.
class GainSolution {
  const GainSolution({
    required this.gains,
    required this.pairs,
    required this.sweeps,
  });

  /// Har kadr uchun koeffitsiyent, kadr indeksi bo'yicha.
  final List<double> gains;

  /// Nechta juft ustma-ust tushgan. `0` bo'lsa hech narsa tuzatilmagan —
  /// hamma koeffitsiyent 1 qoladi.
  final int pairs;

  final int sweeps;

  Map<String, Object?> toJson() => <String, Object?>{
    'gainPairs': pairs,
    'gainSweeps': sweeps,
    'gainMin': gains.isEmpty ? 1.0 : gains.reduce(math.min),
    'gainMax': gains.isEmpty ? 1.0 : gains.reduce(math.max),
  };
}

/// Normal deb hisoblanadigan yorqinlik tarqalishi.
const double kSigmaN = 5;

/// Yo'l qo'yiladigan koeffitsiyent tarqalishi.
const double kSigmaG = 0.12;

/// Langar kuchi — `σN² / σG²`.
///
/// ⚠️ LANGAR SHART, lekin sababi ehtiyotkorlik bilan aytilishi kerak.
///
/// Langarsiz juftlik tenglamalari `g` ga nisbatan BIR JINSLI: agar `g`
/// yechim bo'lsa, `2g` ham, `0.1g` ham yechim. Ya'ni masala faqat
/// NISBATLARNI aniqlaydi, umumiy MASSHTABNI emas — panoramaning butun
/// yorqinligi ixtiyoriy bo'lib qoladi va u oqarib yoki qorayib ketishi
/// mumkin. (Nazariy jihatdan `g = 0` ham yechim; amalda Gauss-Seidel
/// `g = 1` dan boshlab unga tushmaydi, lekin qayerga tushishi butunlay
/// boshlang'ich nuqtaga bog'liq bo'lib qoladi — bu o'lchandi va
/// `gains_test.dart` da qotirilgan.)
///
/// Langar shu masshtabni qotiradi: har koeffitsiyentni 1 ga tortadi.
/// Kuchi — «qancha yorqinlik farqi normal» ni «qancha koeffitsiyent
/// farqiga yo'l qo'yiladi» ga nisbatan qo'yadi. Bu OpenCV ning o'z
/// `GainCompensator` i tanlagan muvozanatning aynan o'zi.
const double kGainAnchor = (kSigmaN * kSigmaN) / (kSigmaG * kSigmaG);

/// Ikki kadr markazi orasidagi burchak, radian.
///
/// Matritsaning 3-ustuni (`[2], [5], [8]`) — kameraning optik o'qi.
double separationRad(List<double> a, List<double> b) {
  final double d = a[2] * b[2] + a[5] * b[5] + a[8] * b[8];
  // ⚠️ QISILADI: suzuvchi nuqta xatosi skalyar ko'paytmani 1.0000001
  // qilib qo'yishi mumkin va `acos` NaN qaytaradi — keyin juft
  // «juda uzoq» deb tashlanadi va tenglashtirish jimgina yomonlashadi.
  return math.acos(d.clamp(-1.0, 1.0));
}

/// Bundan uzoq kadrlar ustma-ust tusha OLMAYDI, ya'ni solishtirilmaydi.
///
/// 55° — kadrning o'z ko'rish burchagidan (~41° gorizontal, ~67°
/// diagonal) kelib chiqadi. Kengaytirish bekor ish qo'shadi, toraytirish
/// esa haqiqiy juftlarni yo'qotadi.
const double kMaxPairSepRad = 55 * math.pi / 180;

/// Juft sohasi shundan kichik bo'lsa e'tiborga OLINMAYDI.
///
/// Kichik ustma-ustlikda o'rtacha yorqinlik shovqinga aylanadi va u
/// butun yechimni tortib ketishi mumkin.
const double kMinPairArea = 12;

/// Koeffitsiyent shu oraliqdan chiqmaydi.
///
/// Chegara YECHIMNI EMAS, uning zararini cheklaydi: bitta noto'g'ri
/// juft (masalan ikki kadr orasida odam o'tib qolgan) koeffitsiyentni
/// ma'nosiz qiymatga surib yuborishi mumkin, o'shanda kadr butunlay
/// oqarib yoki qorayib ketardi.
const double kGainMin = 0.5;
const double kGainMax = 2.0;

/// Gauss-Seidel yechuvchisi — SOF funksiya.
///
/// [initial] FAQAT sinov uchun: langarsiz masala masshtabga befarq, ya'ni
/// natija boshlang'ich nuqtaga bog'liq bo'lib qoladi. Langar bor bo'lsa
/// boshlang'ich nuqta natijaga ta'sir qilmaydi.
///
/// [iBar] — `iBar[i][j]` = i-kadrning i va j UMUMIY sohasidagi o'rtacha
/// yorqinligi. [area] — o'sha umumiy sohaning kattaligi (simmetrik).
///
/// Ajratilgani sababi: butun mantiq shu yerda va u tasvirsiz,
/// proyeksiyasiz, telefonsiz tekshiriladi. Rasm tomoni
/// ([pairwiseBrightness]) faqat shu ikki matritsani to'ldiradi.
GainSolution solveGains(
  List<List<double>> iBar,
  List<List<double>> area, {
  double anchor = kGainAnchor,
  int sweeps = 60,
  double clampLo = kGainMin,
  double clampHi = kGainMax,
  double initial = 1,
}) {
  final int n = iBar.length;
  final g = List<double>.filled(n, initial);
  if (n == 0) return GainSolution(gains: g, pairs: 0, sweeps: 0);

  for (int sweep = 0; sweep < sweeps; sweep++) {
    for (int i = 0; i < n; i++) {
      double diagTerm = 0, rhs = 0, nI = 0;
      for (int j = 0; j < n; j++) {
        if (j == i || area[i][j] <= 0) continue;
        nI += area[i][j];
        diagTerm += area[i][j] * iBar[i][j] * iBar[i][j];
        rhs += area[i][j] * iBar[i][j] * iBar[j][i] * g[j];
      }
      // Hech kim bilan ustma-ust tushmagan kadr O'Z HOLICHA qoladi
      // (koeffitsiyenti 1).
      //
      // Bu tekshiruv ORTIQCHA — `nI == 0` bo'lganda `diagTerm` ham nol
      // bo'lib qoladi va pastdagi `diagTerm > 1e-9` shartiga tushmaydi,
      // ya'ni `g[i]` baribir o'zgarmaydi. (Mutatsiya bilan tekshirildi:
      // bu qatorni olib tashlash birorta testni yiqitmadi.) Saqlanadi,
      // chunki niyatni ochiq aytadi — lekin HIMOYA emas, himoya
      // pastdagi shartda.
      if (nI <= 0) continue;
      diagTerm += nI * anchor;
      rhs += nI * anchor;
      if (diagTerm > 1e-9) g[i] = (rhs / diagTerm).clamp(clampLo, clampHi);
    }
  }

  int pairs = 0;
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      if (area[i][j] > 0) pairs++;
    }
  }
  return GainSolution(gains: g, pairs: pairs, sweeps: sweeps);
}

/// Juftlik yorqinligi matritsalarini to'ldiradi.
///
/// [brightness] — `(i, j)` juftining UMUMIY sohasidagi o'lchov:
/// `(meanI, meanJ, area)`, yoki ustma-ustlik yo'q bo'lsa `null`.
/// Chaqiruvchi uni kichik kulrang tuvaldan hisoblaydi (256×128 yetadi —
/// bu yerda detal emas, o'rtacha yorqinlik kerak).
///
/// [rotations] berilsa 55° dan uzoq juftlar UMUMAN o'lchanmaydi: ular
/// ustma-ust tusha olmaydi va har juftni tekshirish n² ish.
({List<List<double>> iBar, List<List<double>> area}) pairwiseBrightness(
  int n,
  (double meanI, double meanJ, double area)? Function(int i, int j) brightness, {
  List<List<double>>? rotations,
  double maxSepRad = kMaxPairSepRad,
  double minArea = kMinPairArea,
}) {
  final iBar = List<List<double>>.generate(n, (_) => List<double>.filled(n, 0));
  final area = List<List<double>>.generate(n, (_) => List<double>.filled(n, 0));

  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      if (rotations != null &&
          separationRad(rotations[i], rotations[j]) > maxSepRad) {
        continue;
      }
      final m = brightness(i, j);
      if (m == null || m.$3 < minArea) continue;
      iBar[i][j] = m.$1;
      iBar[j][i] = m.$2;
      area[i][j] = m.$3;
      area[j][i] = m.$3;
    }
  }
  return (iBar: iBar, area: area);
}
