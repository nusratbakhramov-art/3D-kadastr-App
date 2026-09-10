import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/models/stitch_outcome.dart';

/// `selectBand` — qamrovni PIKSELDAN o'lchash.
///
/// Bu funksiya ataylab sof: manbada xato aynan shu yerda yashagan va u
/// qurilmasiz, tikish quvurisiz tekshirilishi mumkin.
///
/// XATONING TARIXI. Band `rows ~/ 2` dan — tuvalning vertikal markazidan —
/// o'stirilardi, "gorizont o'rtada" degan taxmin bilan. Foydalanuvchi
/// ilovaning o'z taklifini qabul qilib qutblarni (±90) suratga olishi bilan
/// o'sha kadrlar tuvalni gorizont bandidan uzoqqa cho'zadi va markaziy
/// qator QORA bo'shliqqa tushib qoladi. Keyin narvonning har pog'onasi
/// hech qachon piksel bo'lmagan qatorda yiqilardi va mukammal 42 kadrli
/// halqa «bir joyda turib to'liq 360° aylan» degan — foydalanuvchi
/// allaqachon bajargan — maslahat bilan rad etilardi.
void main() {
  const cols = 1000;
  const full = cols * 255;

  /// [rows] qatorli tuval; [covered] dagi indekslar to'liq qamralgan.
  List<int> canvas(int rows, Iterable<int> covered, {double fraction = 1.0}) {
    final out = List<int>.filled(rows, 0);
    for (final y in covered) {
      out[y] = (full * fraction).round();
    }
    return out;
  }

  group('selectBand', () {
    test('to‘liq qamralgan tuvalda butun balandlik band bo‘ladi', () {
      final scan = selectBand(canvas(10, List.generate(10, (i) => i)), cols);
      expect(scan.band, isNotNull);
      expect(scan.band!.top, 0);
      expect(scan.band!.height, 10);
      expect(scan.bestFraction, closeTo(1.0, 1e-9));
      expect(scan.usedFraction, 0.995);
    });

    test('gorizont MARKAZDAN SILJIGAN bo‘lsa ham topiladi', () {
      // Aynan qutb kadrlari keltirgan holat: piksellar tuvalning yuqori
      // uchdan birida, markaz (y=50) esa BO'SH. Markazdan o'stiradigan eski
      // mantiq bu yerda band topa olmasdi.
      final scan = selectBand(canvas(100, [10, 11, 12, 13, 14]), cols);
      expect(scan.bestRow, inInclusiveRange(10, 14));
      expect(scan.band, isNotNull, reason: 'markazdan tashqarida ham band bor');
      expect(scan.band!.top, 10);
      expect(scan.band!.height, 5);
      expect(scan.rows, 100);
    });

    test('band uzluksiz — teshikdan o‘tib ketmaydi', () {
      // 10..12 va 20..22 qamralgan. Band faqat bittasini olishi kerak,
      // ular orasidagi qora 13..19 ni yutib yubormasligi kerak.
      final scan = selectBand(
        canvas(30, [10, 11, 12, 20, 21, 22]),
        cols,
      );
      expect(scan.band!.height, 3);
      expect(scan.band!.top, anyOf(10, 20));
    });

    test('narvon yumshaydi: 0.98 qator 0.97 pog‘onada qabul qilinadi', () {
      // Gorizont yonidagi bitta zaif chok 0.995 dan o'tmaydi, lekin 97%
      // tayyor panorama uchun xato qaytarish hech kimga yordam bermaydi.
      final scan = selectBand(canvas(10, [4, 5], fraction: 0.98), cols);
      expect(scan.usedFraction, 0.97);
      expect(scan.band, isNotNull);
      expect(scan.bestFraction, closeTo(0.98, 1e-6));
    });

    test('narvonning har pog‘onasi ishlatiladi', () {
      for (final f in <double>[0.995, 0.97, 0.90, 0.80]) {
        final scan = selectBand(canvas(10, [5], fraction: f), cols);
        expect(scan.usedFraction, f, reason: '$f pog‘onasi ishlamadi');
      }
    });

    test('0.80 dan past qator band BERMAYDI, lekin o‘lchov qaytadi', () {
      final scan = selectBand(canvas(10, [5], fraction: 0.43), cols);
      expect(scan.band, isNull, reason: 'burilish yopilmagan');
      expect(scan.usedFraction, isNull);
      // Yiqilishdan keyin o'lchovlar YO'QOLMASLIGI kerak: «eng yaxshi qator
      // 43% qamragan» bilan «99% qamragan, lekin siljigan» butunlay boshqa
      // nosozlik hisoboti.
      expect(scan.bestFraction, closeTo(0.43, 1e-6));
      expect(scan.bestRow, 5);
      expect(scan.rows, 10);
    });

    test('bitta qorong‘i eshik butun qatorni veto QILMAYDI', () {
      // 99.6% — haqiqiy interyerda odatiy. Bu funksiya ushlash uchun
      // yaratilgan qora tirqishlar qatorning 0.5% iga o'xshamaydi.
      final scan = selectBand(canvas(10, [5], fraction: 0.996), cols);
      expect(scan.usedFraction, 0.995);
      expect(scan.band, isNotNull);
    });

    test('butunlay qora tuvalda band yo‘q va yiqilmaydi', () {
      final scan = selectBand(List<int>.filled(10, 0), cols);
      expect(scan.band, isNull);
      expect(scan.bestFraction, 0);
    });

    test('bo‘sh ro‘yxatda yiqilmaydi', () {
      final scan = selectBand(const <int>[], cols);
      expect(scan.band, isNull);
      expect(scan.rows, 0);
      expect(scan.bestFraction, 0);
    });
  });

  group('BandScan.toJson', () {
    test('band bor: hamma o‘lchov chiqadi', () {
      final json = selectBand(canvas(10, [4, 5]), cols).toJson();
      expect(json['panoRows'], 10);
      expect(json['bestRow'], anyOf(4, 5));
      expect(json['bestRowCoverage'], 1.0);
      expect(json['acceptedAtFraction'], 0.995);
      expect(json['bandTop'], 4);
      expect(json['bandHeight'], 2);
    });

    test('band yo‘q: band kalitlari BO‘LMAYDI', () {
      final json = selectBand(canvas(10, [5], fraction: 0.4), cols).toJson();
      expect(json.containsKey('bandTop'), isFalse);
      expect(json.containsKey('bandHeight'), isFalse);
      expect(json['acceptedAtFraction'], isNull);
      expect(json['bestRowCoverage'], 0.4);
    });

    test('qamrov 4 xonaga yaxlitlanadi', () {
      // `report.json` da 0.9799999999999999 ko'rinmasligi uchun.
      final json = selectBand(canvas(10, [5], fraction: 1 / 3), cols).toJson();
      expect(json['bestRowCoverage'], 0.3333);
    });
  });

  group('StitchOutcome', () {
    test('StitchFailure o‘lchovlarni olib keladi', () {
      const f = StitchFailure(
        'halqa yopilmadi',
        needsMoreImages: true,
        diagnostics: <String, Object?>{'bestRowCoverage': 0.43},
      );
      expect(f.needsMoreImages, isTrue);
      expect(f.diagnostics['bestRowCoverage'], 0.43);
    });

    test('sukut bo‘yicha needsMoreImages false', () {
      const f = StitchFailure('ichki xato');
      expect(f.needsMoreImages, isFalse);
      expect(f.diagnostics, isEmpty);
    });

    test('StitchSuccess qamrovni ALOHIDA saqlaydi', () {
      // 4096×2048 nisbati 180° beradi, haqiqiy qamrov esa 123.8 bo'lishi
      // mumkin — farq ko'ruvchi qutblarga o'rab qo'ygan qora.
      const s = StitchSuccess(
        path: '/tmp/p.jpg',
        width: 4096,
        height: 2048,
        verticalCoverDeg: 123.8,
      );
      expect(s.height * 360 / s.width, 180);
      expect(s.verticalCoverDeg, 123.8);
    });

    test('sealed: ikki holatdan boshqasi yo‘q', () {
      const outcomes = <StitchOutcome>[
        StitchSuccess(path: 'a', width: 1, height: 1, verticalCoverDeg: 1),
        StitchFailure('b'),
      ];
      for (final o in outcomes) {
        final label = switch (o) {
          StitchSuccess() => 'ok',
          StitchFailure() => 'fail',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
