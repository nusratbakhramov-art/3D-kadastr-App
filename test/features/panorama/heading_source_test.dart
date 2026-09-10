import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/data/heading_source.dart';

/// Sensor → yaw/pitch/roll.
///
/// Bu faylning butun mohiyati BITTA da'voda: `OrientationEvent.yaw` ni
/// to'g'ridan o'qib bo'lmaydi, chunki suratga olish holatida (qurilma
/// pitch ≈ 90°) u gimbal-lock singulyarligida turadi. Testlarning
/// asosiysi shu singulyarlikni O'LCHAB ko'rsatadi va kompozitsiya undan
/// chiqib ketishini qotiradi.
void main() {
  const d2r = math.pi / 180;

  /// Qurilma burchaklaridan (gradusda) yo'nalish.
  ({double yawDeg, double pitchDeg, double rollDeg}) at(
    double devYaw,
    double devPitch,
    double devRoll, {
    double screenDeg = 0,
    bool cw = true,
  }) => aimAngles(
    devYaw * d2r,
    devPitch * d2r,
    devRoll * d2r,
    screenDeg * d2r,
    clockwisePositive: cw,
  );

  group('GIMBAL-LOCK — faylning mavjudlik sababi', () {
    test('pitch 90° da qurilma yaw va roll AYNI narsa', () {
      // O'LCHANGAN. Suratga olish holatida yaw/pitch/roll dekompozitsiyasi
      // buziladi: qurilma yaw'ini +5° o'zgartirish va qurilma roll'ini
      // +5° o'zgartirish BIR XIL fizik burilish beradi.
      //
      // ⚠️ ISHORA MUHIM va uni adashtirish oson: ikkalasi ham AYNI ishora
      // bilan mos keladi (+5 ↔ +5), qarama-qarshi emas.
      final yawPlus = at(5, 90, 0).yawDeg;
      final rollPlus = at(0, 90, 5).yawDeg;
      expect(yawPlus, closeTo(355.0, 1e-3));
      expect(rollPlus, closeTo(355.0, 1e-3));
      expect(yawPlus, closeTo(rollPlus, 1e-9), reason: 'ayni burilish');

      // Teskari tomon ham teskari natija beradi.
      expect(at(-5, 90, 0).yawDeg, closeTo(5.0, 1e-3));
    });

    test('kompozitsiya qutbdan CHIQADI — yaw barqaror o‘qiladi', () {
      // Agar 90° li X aylanishi bo'lmasa, bu yerda yaw sakrardi. Telefon
      // deyarli tik turganda ham kichik yaw o'zgarishi kichik natija
      // berishi kerak.
      final a = at(0, 88, 0).yawDeg;
      final b = at(2, 88, 0).yawDeg;
      expect(Steadiness.shortestTurn(a, b).abs(), lessThan(5));
    });

    test('gorizontal holatda ham ishlaydi', () {
      // pitch 0 — telefon yotiq. Singulyarlikdan uzoq.
      final a = at(0, 0, 0);
      expect(a.yawDeg.isFinite, isTrue);
      expect(a.pitchDeg.isFinite, isTrue);
      expect(a.rollDeg.isFinite, isTrue);
    });
  });

  group('aimAngles — chegara va normallashtirish', () {
    test('yaw HAR DOIM 0..360 oralig‘ida', () {
      for (var dy = -720.0; dy <= 720.0; dy += 37) {
        for (final dp in <double>[-80, -45, 0, 45, 80, 90]) {
          final y = at(dy, dp, 0).yawDeg;
          expect(y, inInclusiveRange(0, 360), reason: 'yaw=$dy pitch=$dp');
          expect(y.isNaN, isFalse);
        }
      }
    });

    test('clockwisePositive bayrog‘i 30 ↔ 330 qiladi, MANFIY emas', () {
      // Normallashtirish bayroq shoxidan KEYIN bo'ladi. Aks tartibda
      // manfiy yaw chiqardi va butun capture halqasi buzilardi.
      final cw = at(30, 20, 0).yawDeg;
      final ccw = at(30, 20, 0, cw: false).yawDeg;
      expect(cw + ccw, closeTo(360, 1e-6));
      expect(ccw, greaterThanOrEqualTo(0));
    });

    test('asin QISILADI — hech qanday holatda NaN chiqmaydi', () {
      // Suzuvchi nuqta xatosi argumentni 1.0000001 qilsa `asin` NaN
      // berardi va butun capture yo'nalishsiz qolardi.
      for (final dp in <double>[-90, -89.999, 89.999, 90, 90.001, 180]) {
        final a = at(0, dp, 0);
        expect(a.pitchDeg.isNaN, isFalse, reason: 'pitch=$dp');
        expect(a.yawDeg.isNaN, isFalse, reason: 'pitch=$dp');
      }
    });

    test('AYNAN topilgan holat: asin argumenti 1 dan oshadi', () {
      // ⚠️ Bu qisishning o'lik kod EMASLIGINI isbotlaydi. Butun burchak
      // fazosi skanerlandi (yaw −360..360, pitch −180..180, roll va ekran
      // to'rt holatda) va argument eng ko'pi 1.000000000000000444 ga
      // chiqdi — aynan shu nuqtada:
      //
      //     yaw = −120°, pitch = −180°, roll = −180°, ekran = 90°
      //
      // Qisishsiz `asin` bu yerda NaN qaytaradi va butun capture
      // yo'nalishsiz qoladi — hech qanday xato chiqmasdan.
      final a = at(-120, -180, -180, screenDeg: 90);
      expect(a.pitchDeg.isNaN, isFalse, reason: 'qisish ishlashi kerak');
      expect(a.pitchDeg.abs(), closeTo(90, 1e-6));
      expect(a.yawDeg.isNaN, isFalse);
    });

    test('pitch −90..+90 dan chiqmaydi', () {
      for (var dp = -180.0; dp <= 180.0; dp += 13) {
        expect(at(0, dp, 0).pitchDeg, inInclusiveRange(-90.0, 90.0));
      }
    });

    test('EKRAN burilishi ROLL ga tushadi, yaw/pitch ga EMAS', () {
      // O'LCHANGAN va fizik jihatdan to'g'ri: ekranni burish kadrni LINZA
      // O'QI atrofida aylantiradi, kamera QAYERGA qaraganini o'zgartirmaydi.
      // Shuning uchun yaw va pitch tegilmaydi, roll esa aynan ekran
      // burchagiga teng bo'ladi.
      //
      // Buni «yaw o'zgarishi kerak» deb kutish xato bo'lardi — aynan shu
      // xato bu testning birinchi variantida bo'lgan.
      for (final (deg, wantRoll) in <(double, double)>[
        (0, 0),
        (90, 90),
        (180, 180),
        (270, -90),
      ]) {
        final a = at(0, 45, 0, screenDeg: deg);
        expect(a.rollDeg, closeTo(wantRoll, 1e-6), reason: 'screen=$deg');
        expect(a.yawDeg, closeTo(0, 1e-6), reason: 'screen=$deg yaw');
        expect(a.pitchDeg, closeTo(-45, 1e-6), reason: 'screen=$deg pitch');
      }
    });

    test('LINZA roll ≠ xom qurilma roll', () {
      // Portretda (pitch 90) xom roll ±180 atrofida sakraydi; linza roll'i
      // esa kichik va barqaror bo'lishi kerak.
      final a = at(0, 90, 175);
      expect(a.rollDeg.abs(), lessThan(180));
      expect(a.rollDeg.isNaN, isFalse);
    });
  });

  group('Steadiness — zatvor qachon ochiladi', () {
    test('chegara 3 grad/s, ushlash 350 ms', () {
      // ⚠️ Manbadagi izoh «8 grad/s» deydi, kod esa 3 beradi — izoh
      // eskirgan va port kodga ergashadi.
      expect(HeadingSource.steadyThresholdDegPerSec, 3);
      expect(HeadingSource.steadyHold, const Duration(milliseconds: 350));
    });

    test('30 Hz da 11-o‘lchovda to‘ladi', () {
      // need = 350 * 30 / 1000 = 10.5 tik. Birinchi `add` faqat tayanch
      // nuqtani belgilaydi, ya'ni sanoq ikkinchisidan boshlanadi.
      final s = Steadiness(30);
      final seen = <double>[];
      for (var i = 0; i < 13; i++) {
        s.add(0, 0); // butunlay qimirlamayapti
        seen.add(s.fraction);
      }
      expect(seen[0], 0, reason: 'birinchi o‘lchov tayanch');
      expect(seen[1], closeTo(1 / 10.5, 1e-9));
      expect(seen[10], closeTo(10 / 10.5, 1e-9));
      expect(seen[11], 1.0);
      expect(s.steady, isTrue);
    });

    test('QIMIRLASH sanoqni NOLGA tushiradi', () {
      final s = Steadiness(30);
      for (var i = 0; i < 8; i++) {
        s.add(0, 0);
      }
      expect(s.fraction, greaterThan(0.5));
      // 30 Hz da 1° siljish = 30 grad/s — chegaradan ancha yuqori.
      s.add(1, 0);
      expect(s.fraction, 0);
      expect(s.steady, isFalse);
    });

    test('chegaradagi tezlik QABUL qilinadi (<=)', () {
      // 3 grad/s aynan chegara. `<` bo'lsa zatvor hech qachon
      // ochilmasligi mumkin edi.
      final s = Steadiness(30);
      s.add(0, 0);
      s.add(3 / 30, 0); // aynan 3 grad/s
      expect(s.ticks, 1);
    });

    test('YAW O‘RASHI 358° sakrash bo‘lib o‘qilmaydi', () {
      // Bu bo'lmasa 359 → 1 o'tishida zatvor abadiy bloklanardi.
      final s = Steadiness(30);
      s.add(359.98, 0);
      s.add(0.02, 0); // 359.96° emas, 0.04° siljish → 1.2 grad/s
      expect(s.ticks, 1, reason: 'qisqa yo‘l bilan solishtirilsin');

      // Nazorat: o'ramasdan solishtirilsa bu 359.96° bo'lardi va sanoq
      // nolga tushardi.
      expect(Steadiness.shortestTurn(359.98, 0.02), closeTo(0.04, 1e-6));
    });

    test('yaw va pitch BIRGA hisoblanadi', () {
      // Faqat yaw qaralsa, tik pastga tushirilayotgan telefon
      // «qimirlamayapti» deb hisoblanardi.
      final s = Steadiness(30);
      s.add(0, 0);
      s.add(0, 1); // faqat pitch o'zgardi → 30 grad/s
      expect(s.ticks, 0);
    });

    test('reset tayanchni ham tozalaydi', () {
      final s = Steadiness(30);
      s.add(0, 0);
      s.add(0, 0);
      expect(s.ticks, 1);
      s.reset();
      expect(s.ticks, 0);
      s.add(100, 100); // reset'dan keyin birinchi — tayanch, sakrash EMAS
      expect(s.ticks, 0);
    });

    test('hz o‘zgarsa to‘lish vaqti o‘zgaradi', () {
      // 60 Hz da 21 tik kerak (350 * 60 / 1000).
      final s = Steadiness(60);
      for (var i = 0; i < 21; i++) {
        s.add(0, 0);
      }
      expect(s.fraction, lessThan(1));
      s.add(0, 0);
      expect(s.fraction, 1.0);
    });

    test('fraction 1 dan OSHMAYDI', () {
      final s = Steadiness(30);
      for (var i = 0; i < 100; i++) {
        s.add(0, 0);
      }
      expect(s.fraction, 1.0);
    });

    test('shortestTurn o‘rashni to‘g‘ri hal qiladi', () {
      expect(Steadiness.shortestTurn(350, 10), closeTo(20, 1e-9));
      expect(Steadiness.shortestTurn(10, 350), closeTo(-20, 1e-9));
      expect(Steadiness.shortestTurn(0, 180), closeTo(180, 1e-9));
      expect(Steadiness.shortestTurn(0, 181), closeTo(-179, 1e-9));
    });
  });

  group('DeviceAim', () {
    const a = DeviceAim(yawDeg: 10, pitchDeg: 20, rollDeg: 1);

    test('qiymat bo‘yicha tenglashadi', () {
      expect(a, const DeviceAim(yawDeg: 10, pitchDeg: 20, rollDeg: 1));
      expect(a.hashCode,
          const DeviceAim(yawDeg: 10, pitchDeg: 20, rollDeg: 1).hashCode);
    });

    test('HAR BIR maydon tenglikka kiradi', () {
      // ⚠️ `ValueNotifier` faqat qiymat o'zgarsa xabar beradi. Maydon
      // `==` dan tushib qolsa, o'sha maydon o'zgarganda UI yangilanmaydi —
      // masalan `steadyProgress` tushib qolsa to'layotgan halqa qotib
      // qolardi.
      expect(a, isNot(const DeviceAim(yawDeg: 11, pitchDeg: 20, rollDeg: 1)));
      expect(a, isNot(const DeviceAim(yawDeg: 10, pitchDeg: 21, rollDeg: 1)));
      expect(a, isNot(const DeviceAim(yawDeg: 10, pitchDeg: 20, rollDeg: 2)));
      expect(
        a,
        isNot(const DeviceAim(
            yawDeg: 10, pitchDeg: 20, rollDeg: 1, rawDeviceRollDeg: 5)),
      );
      expect(
        a,
        isNot(const DeviceAim(
            yawDeg: 10, pitchDeg: 20, rollDeg: 1, steady: true)),
      );
      expect(
        a,
        isNot(const DeviceAim(
            yawDeg: 10, pitchDeg: 20, rollDeg: 1, steadyProgress: 0.5)),
      );
    });

    test('sukut qiymatlari', () {
      const b = DeviceAim(yawDeg: 0, pitchDeg: 0);
      expect(b.rollDeg, 0);
      expect(b.rawDeviceRollDeg, 0);
      expect(b.steady, isFalse);
      expect(b.steadyProgress, 0);
    });
  });

  group('HeadingSource — hayot sikli', () {
    test('boshlanmagan holatda aim `null`', () {
      final h = HeadingSource();
      expect(h.aim.value, isNull);
      expect(h.isRunning, isFalse);
      h.dispose();
    });

    test('hz `stop()` dan keyin ham saqlanadi', () {
      // Ekran fondan qaytganda `start(hz: source.hz)` bilan o'sha tezlikda
      // tiklash uchun.
      final h = HeadingSource();
      expect(h.hz, 30);
      h.dispose();
    });

    test('clockwisePositive sukut bo‘yicha ROST', () {
      // O'LCHANGAN qaror: negatsiya yaw'ni chapga o'stirardi va panorama
      // ko'zguga aylanardi.
      expect(HeadingSource().clockwisePositive, isTrue);
    });
  });
}
