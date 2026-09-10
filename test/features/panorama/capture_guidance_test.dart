import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/models/capture_guidance.dart';

/// Tekis ushlangan, shimolga qaragan telefon; 4:3 portret kadr.
TargetSight sight(
  double targetYaw,
  double targetPitch, {
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
}) => sightTarget(
  yawDeg: yaw,
  pitchDeg: pitch,
  rollDeg: roll,
  targetYawDeg: targetYaw,
  targetPitchDeg: targetPitch,
  imageWidth: 3000,
  imageHeight: 4000,
  longSideFovDeg: 67.3,
  toleranceDeg: 1.5,
);

void main() {
  group('nishonni ko\'rish', () {
    test('to\'ppa-to\'g\'ri oldidagi nishon markazda va «aligned»', () {
      final TargetSight s = sight(0, 0);
      expect(s.angleErrorDeg, closeTo(0, 1e-6));
      expect(s.offsetPixels, isNotNull);
      expect(s.offsetPixels!.dx, closeTo(0, 1e-6));
      expect(s.offsetPixels!.dy, closeTo(0, 1e-6));
      expect(s.onScreen, isTrue);
      expect(s.level, GuidanceLevel.aligned);
    });

    // (i) HECH QACHON jimgina almashmasligi kerak bo'lgan belgi. Bu ekranda
    // «o'ngga burilish» yaw'ni OSHIRISH degani — banner ham, halqa ham shunday
    // deydi. Demak yaw'ni oshirish bilan yetiladigan nishon O'NGGA chizilishi
    // va strelka O'NGNI ko'rsatishi shart.
    test('o\'ngdagi nishon o\'ngga chiziladi', () {
      final TargetSight s = sight(10, 0);
      expect(s.offsetPixels!.dx, greaterThan(0));
      expect(s.arrowRadians, closeTo(0, 1e-6));
    });

    test('chapdagi nishon chapga chiziladi', () {
      final TargetSight s = sight(-10, 0);
      expect(s.offsetPixels!.dx, lessThan(0));
      expect(s.arrowRadians.abs(), closeTo(math.pi, 1e-5));
    });

    test('yuqoridagi nishon yuqorida — ekranda y KICHIKROQ', () {
      final TargetSight s = sight(0, 10);
      expect(s.offsetPixels!.dy, lessThan(0));
      // Ekranda y pastga o'sadi, ya'ni «yuqori» — chorak burilish MANFIY.
      expect(s.arrowRadians, closeTo(-math.pi / 2, 1e-5));
    });

    test('pastdagi nishon pastda', () {
      expect(sight(0, -10).offsetPixels!.dy, greaterThan(0));
      expect(sight(0, -10).arrowRadians, closeTo(math.pi / 2, 1e-5));
    });

    test('burchak xatosi — ikki yo\'nalish orasidagi HAQIQIY burchak', () {
      expect(sight(30, 0).angleErrorDeg, closeTo(30, 1e-6));
      expect(sight(0, 30).angleErrorDeg, closeTo(30, 1e-6));
      // Ikkisining yig'indisi EMAS: sferada ular qo'shilmaydi, birikadi.
      expect(sight(30, 30).angleErrorDeg, lessThan(60));
      expect(sight(30, 30).angleErrorDeg, greaterThan(40));
    });

    test('orqadagi nishonda pozitsiya yo\'q, faqat yo\'nalish bor', () {
      final TargetSight s = sight(150, 0);
      expect(s.offsetPixels, isNull);
      expect(s.onScreen, isFalse);
      // Orqada va o'ngda bo'lsa ham «o'ngga buril» degani.
      expect(s.arrowRadians.abs(), lessThan(math.pi / 2));
      expect(s.angleErrorDeg, closeTo(150, 1e-6));
    });

    test('kadr chetidan chiqib ketgan nishon «ekranda» deb sanalmaydi', () {
      // Kadr ~53° kenglikda, ya'ni o'qdan 40° chetdagi nishon telefon oldida
      // bo'lsa ham kadrga sig'maydi.
      final TargetSight s = sight(40, 0);
      expect(s.offsetPixels, isNotNull, reason: 'baribir oldida');
      expect(s.onScreen, isFalse);
    });

    test('nishon tomonga burilish uni yaqinlashtiradi, uzoqlashtirmaydi', () {
      final Offset far = sight(20, 0).offsetPixels!;
      final Offset near = sight(20, 0, yaw: 10).offsetPixels!;
      expect(near.dx.abs(), lessThan(far.dx.abs()));
    });

    // (j) Butun overlay shunga tayanadi: eshik ustidagi belgi ESHIKDA turishi
    // kerak. Ekrandagi o'rni telefon burilganda noto'g'ri tomonga siljisa,
    // belgi ko'rsatayotgan narsasidan sirg'alib tushadi.
    test('belgi devordagi joyiga YOPISHIB turadi', () {
      final double focal = focalPx(3000, 4000, 67.3);
      const double d2r = math.pi / 180;
      const double target = 20;
      double x(double phoneYaw) =>
          sight(target, 0, yaw: phoneYaw).offsetPixels!.dx;

      // Pinhole kadrida qo'zg'almas nuqtaning o'rni `focal · tan(o'qdan
      // burchak)`, ya'ni telefonni burish uni ikki TANGENSNING FARQI qadar
      // siljitadi, doimiy tezlik bilan emas. Aynan shu sababli belgi
      // proyeksiya qilinadi, burchakka proporsional qo'yilmaydi: kadr chetida
      // tasvir markazdagidan sezilarli tez sirg'aladi.
      for (final double turn in <double>[1, 2, 5, 10]) {
        final double moved = x(0) - x(turn);
        final double expected =
            focal * (math.tan(target * d2r) - math.tan((target - turn) * d2r));
        expect(
          moved,
          closeTo(expected, expected.abs() * 0.01),
          reason: 'o\'ngga $turn daraja burilgandan keyin',
        );
      }
    });

    test('nishondan o\'tib ketilsa u boshqa tomonga o\'tadi', () {
      expect(sight(10, 0, yaw: 0).offsetPixels!.dx, greaterThan(0));
      expect(sight(10, 0, yaw: 20).offsetPixels!.dx, lessThan(0));
    });

    test('roll belgini aylantiradi, lekin burchak xatosini o\'zgartirmaydi', () {
      // Roll optik o'qni qimirlatmaydi (rotation_test (d)), demak xato ham
      // o'zgarmaydi; faqat belgi kadr ichida aylanadi.
      final TargetSight upright = sight(10, 0);
      final TargetSight tilted = sight(10, 0, roll: 30);
      expect(tilted.angleErrorDeg, closeTo(upright.angleErrorDeg, 1e-9));
      expect(tilted.level, upright.level);
      final double r0 = upright.offsetPixels!.distance;
      expect(tilted.offsetPixels!.distance, closeTo(r0, 1e-6));
      expect(tilted.offsetPixels!.dy.abs(), greaterThan(1));
    });

    test('telefon yaqinlashgani sari ko\'rsatuv qattiqlashadi', () {
      expect(sight(40, 0).level, GuidanceLevel.far);
      expect(sight(10, 0).level, GuidanceLevel.approaching);
      expect(sight(3, 0).level, GuidanceLevel.highlighted);
      expect(sight(1, 0).level, GuidanceLevel.aligned);
    });

    test('«aligned» halqadan OLDIN yonmaydi', () {
      // Kengroq ko'rsatuv chegarasi reticle'ni yashil qilib, capture esa
      // suratni rad etib turishi mumkin emas edi.
      final TargetSight s = sightTarget(
        yawDeg: 0,
        pitchDeg: 0,
        targetYawDeg: 1.8,
        targetPitchDeg: 0,
        imageWidth: 3000,
        imageHeight: 4000,
        longSideFovDeg: 67.3,
        toleranceDeg: 1.5,
      );
      expect(s.level, GuidanceLevel.highlighted);
    });
  });
}
