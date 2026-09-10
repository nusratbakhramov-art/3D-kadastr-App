import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/stitch/gains.dart';

/// Ekspozitsiya tenglashtirish.
///
/// Yechuvchi SOF, ya'ni butun mantiq tasvirsiz sinaladi. Eng muhim
/// testlar ikkita: (a) yorug'lik pog'onasi HAQIQATAN tekislanadimi va
/// (b) langar TRIVIAL yechimni to'sadimi — usiz hamma koeffitsiyent
/// nolga tushib panorama qora chiqardi.
void main() {
  /// `n` kadr, faqat qo'shnilar bilan ustma-ust tushadigan halqa.
  ///
  /// [trueBrightness] — har kadrning O'Z ekspozitsiyasi bilan
  /// o'lchagan yorqinligi. Ustma-ust sohada ikkalasi ham AYNAN o'sha
  /// sahnani ko'radi, ya'ni farq faqat ekspozitsiyadan.
  ({List<List<double>> iBar, List<List<double>> area}) ringOf(
    List<double> trueBrightness, {
    double area = 100,
  }) {
    final n = trueBrightness.length;
    return pairwiseBrightness(n, (i, j) {
      final neighbour = (i + 1) % n == j || (j + 1) % n == i;
      if (!neighbour) return null;
      return (trueBrightness[i], trueBrightness[j], area);
    });
  }

  /// Masshtabdan keyin qo'shnilar qanchalik kelishmaydi.
  double worstMismatch(List<double> b, List<double> g) {
    final n = b.length;
    var worst = 0.0;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      worst = math.max(worst, (b[i] * g[i] - b[j] * g[j]).abs());
    }
    return worst;
  }

  group('solveGains — asosiy da’vo', () {
    test('YORUG‘LIK POG‘ONASI tekislanadi', () {
      // Aynan muammoning o'zi: deraza tomonga qaragan kadr (180) va
      // devor tomonga qaragan kadr (100).
      final b = <double>[100, 100, 180, 180, 100, 100];
      final m = ringOf(b);
      final s = solveGains(m.iBar, m.area);
      expect(
        worstMismatch(b, s.gains),
        lessThan(worstMismatch(b, List<double>.filled(6, 1)) / 3),
        reason: 'nomuvofiqlik kamida uch barobar kamayishi kerak',
      );
    });

    test('bir XIL yorqinlikda hech narsa o‘zgarmaydi', () {
      final m = ringOf(<double>[120, 120, 120, 120]);
      final s = solveGains(m.iBar, m.area);
      for (final g in s.gains) {
        expect(g, closeTo(1, 1e-6));
      }
    });

    test('juftlar soni hisoblanadi', () {
      final m = ringOf(<double>[100, 110, 120, 130]);
      expect(solveGains(m.iBar, m.area).pairs, 4);
    });
  });

  group('LANGAR — trivial yechimni to‘sadi', () {
    test('LANGARSIZ yechim faqat NISBATNI aniqlaydi — masshtabni emas', () {
      // Eng aniq dalil: langarsiz tenglamalar `g` ga nisbatan bir
      // jinsli, ya'ni boshlang'ich nuqtani ikki barobar oshirsak
      // natija ham ikki barobar oshadi. Panoramaning butun yorqinligi
      // shu bilan IXTIYORIY bo'lib qoladi — oqarib yoki qorayib
      // ketishi mumkin.
      final m = ringOf(<double>[100, 140, 100, 140]);
      final from1 = solveGains(m.iBar, m.area, anchor: 0, clampHi: 100);
      final from2 =
          solveGains(m.iBar, m.area, anchor: 0, clampHi: 100, initial: 2);
      for (int i = 0; i < 4; i++) {
        expect(from2.gains[i], closeTo(from1.gains[i] * 2, 1e-6));
      }
    });

    test('LANGAR masshtabni QOTIRADI — boshlang‘ich nuqta ahamiyatsiz', () {
      final m = ringOf(<double>[100, 140, 100, 140]);
      final from1 = solveGains(m.iBar, m.area);
      final from2 = solveGains(m.iBar, m.area, initial: 2);
      final fromHalf = solveGains(m.iBar, m.area, initial: 0.5);
      for (int i = 0; i < 4; i++) {
        expect(from2.gains[i], closeTo(from1.gains[i], 1e-6));
        expect(fromHalf.gains[i], closeTo(from1.gains[i], 1e-6));
      }
    });

    test('koeffitsiyentlar 1 ATROFIDA qoladi', () {
      final m = ringOf(<double>[100, 140, 100, 140]);
      final s = solveGains(m.iBar, m.area);
      for (final g in s.gains) {
        expect(g, inInclusiveRange(0.7, 1.4));
      }
    });

    test('langar kuchi σN²/σG² dan hisoblanadi', () {
      expect(kGainAnchor, closeTo(25 / 0.0144, 1e-6));
      expect(kGainAnchor, closeTo(1736.11, 0.01));
    });

    test('KUCHLI langar tuzatishni bo‘g‘adi', () {
      final b = <double>[100, 180, 100, 180];
      final m = ringOf(b);
      final strong = solveGains(m.iBar, m.area, anchor: 1e9);
      for (final g in strong.gains) {
        expect(g, closeTo(1, 1e-3), reason: 'juda kuchli langar = tuzatishsiz');
      }
    });
  });

  group('chegaralar va chetki holatlar', () {
    test('koeffitsiyent [0.5, 2.0] dan CHIQMAYDI', () {
      // Bitta noto'g'ri juft (ikki kadr orasida odam o'tib qolgan)
      // koeffitsiyentni ma'nosiz qiymatga surib yuborishi mumkin.
      final m = pairwiseBrightness(2, (i, j) => (5.0, 250.0, 500.0));
      final s = solveGains(m.iBar, m.area);
      for (final g in s.gains) {
        expect(g, inInclusiveRange(kGainMin, kGainMax));
      }
    });

    test('USTMA-UST TUSHMAGAN kadr o‘z holicha qoladi', () {
      // `nI == 0` — bo'linish 0/0 bo'lardi.
      final m = pairwiseBrightness(3, (i, j) {
        if (i == 0 && j == 1) return (100.0, 120.0, 50.0);
        return null; // 2-kadr yolg'iz
      });
      final s = solveGains(m.iBar, m.area);
      expect(s.gains[2], 1.0);
      expect(s.gains[0].isFinite, isTrue);
      expect(s.pairs, 1);
    });

    test('bo‘sh to‘plam yiqilmaydi', () {
      final s = solveGains(const <List<double>>[], const <List<double>>[]);
      expect(s.gains, isEmpty);
      expect(s.pairs, 0);
    });

    test('juftsiz to‘plamda hamma koeffitsiyent 1', () {
      final m = pairwiseBrightness(4, (i, j) => null);
      final s = solveGains(m.iBar, m.area);
      expect(s.gains, <double>[1, 1, 1, 1]);
      expect(s.pairs, 0);
    });

    test('NOL yorqinlikli juft yechimni buzmaydi', () {
      // Butunlay qorong'i ustma-ustlik (yopiq eshik) — `iBar` nol
      // bo'ladi va `diagTerm` ga hech narsa qo'shmaydi.
      final m = pairwiseBrightness(2, (i, j) => (0.0, 0.0, 100.0));
      final s = solveGains(m.iBar, m.area);
      expect(s.gains.every((g) => g.isFinite), isTrue);
      expect(s.gains, <double>[1, 1], reason: 'langar 1 da ushlab qoladi');
    });

    test('ko‘proq o‘tish yechimni YOMONLASHTIRMAYDI', () {
      // Gauss-Seidel yaqinlashadi; o'tishlar soni to'xtash mezoni emas.
      final b = <double>[100, 100, 180, 180, 100, 100];
      final m = ringOf(b);
      final few = solveGains(m.iBar, m.area, sweeps: 5);
      final many = solveGains(m.iBar, m.area, sweeps: 200);
      expect(
        worstMismatch(b, many.gains),
        lessThanOrEqualTo(worstMismatch(b, few.gains) + 1e-9),
      );
    });

    test('60 o‘tish YAQINLASHISH uchun yetadi', () {
      final b = <double>[90, 130, 200, 110, 160, 95, 140, 175];
      final m = ringOf(b);
      final s60 = solveGains(m.iBar, m.area);
      final s500 = solveGains(m.iBar, m.area, sweeps: 500);
      for (int i = 0; i < 8; i++) {
        // 60 va 500 o'tish orasidagi farq millioninchi ulushda —
        // ya'ni 60 yetadi va qo'shimcha o'tishlar bekor ish.
        expect(s60.gains[i], closeTo(s500.gains[i], 1e-4));
      }
    });
  });

  group('pairwiseBrightness — juft tanlash', () {
    List<List<double>> rots(List<(double, double)> yawPitch) => <List<double>>[
      for (final (y, p) in yawPitch)
        rotationMatrix(y * math.pi / 180, p * math.pi / 180, 0).toList(),
    ];

    test('UZOQ juftlar umuman o‘lchanmaydi', () {
      // 55° dan uzoq kadrlar ustma-ust tusha olmaydi; har juftni
      // tekshirish n² ish.
      final called = <String>[];
      final r = rots(<(double, double)>[(0, 0), (30, 0), (120, 0)]);
      pairwiseBrightness(
        3,
        (i, j) {
          called.add('$i-$j');
          return (100.0, 100.0, 100.0);
        },
        rotations: r,
      );
      expect(called, <String>['0-1'], reason: '0-2 va 1-2 juda uzoq');
    });

    test('separationRad markazlar orasidagi burchakni beradi', () {
      final r = rots(<(double, double)>[(0, 0), (40, 0)]);
      expect(
        separationRad(r[0], r[1]) * 180 / math.pi,
        closeTo(40, 1e-6),
      );
    });

    test('separationRad NaN qaytarmaydi (qisiladi)', () {
      // Suzuvchi nuqta xatosi skalyar ko'paytmani 1.0000001 qilsa
      // `acos` NaN berardi va juft jimgina tashlanardi.
      final a = <double>[0, 0, 1, 0, 0, 0, 0, 0, 1.0000001];
      expect(separationRad(a, a).isNaN, isFalse);
    });

    test('KICHIK ustma-ustlik tashlanadi', () {
      // Kichik sohada o'rtacha yorqinlik shovqinga aylanadi va butun
      // yechimni tortib ketishi mumkin.
      final m = pairwiseBrightness(2, (i, j) => (100.0, 200.0, 5.0));
      expect(m.area[0][1], 0);
      expect(solveGains(m.iBar, m.area).pairs, 0);
    });

    test('matritsalar SIMMETRIK to‘ldiriladi', () {
      final m = pairwiseBrightness(2, (i, j) => (110.0, 90.0, 77.0));
      expect(m.iBar[0][1], 110);
      expect(m.iBar[1][0], 90, reason: 'j ning o‘lchovi teskari yacheykada');
      expect(m.area[0][1], m.area[1][0]);
    });

    test('rotations berilmasa HAMMA juft o‘lchanadi', () {
      var n = 0;
      pairwiseBrightness(4, (i, j) {
        n++;
        return null;
      });
      expect(n, 6, reason: 'C(4,2)');
    });
  });

  test('toJson diagnostikaga min/max qo‘shadi', () {
    final m = ringOf(<double>[100, 180, 100, 180]);
    final j = solveGains(m.iBar, m.area).toJson();
    expect(j['gainPairs'], 4);
    expect(j['gainSweeps'], 60);
    expect(j['gainMin'], lessThanOrEqualTo(j['gainMax']! as double));
  });
}
