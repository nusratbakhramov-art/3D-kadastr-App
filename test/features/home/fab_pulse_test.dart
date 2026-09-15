import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/home/widgets/fab_pulse.dart';

/// Bosh ekrandagi ikki tugmaning "tirik" halqasi.
///
/// ⚠️ ENG MUHIM XULQ — TO'XTASH. Takrorlanuvchi animatsiya har kadrda
/// qayta chizadi; tugma ko'rinmay turganda ham aylanaverishi quvvat
/// yeydi va buni na `analyze`, na ekranga qarash ko'rsatadi — faqat
/// batareya. Shuning uchun testda kadr rejalashtirilgani tekshiriladi.
void main() {
  group('PulsePainter — geometriya', () {
    const size = Size.square(fabSize);

    ({double radius, double alpha}) ring(double t, int index) {
      // Painter'ning o'z formulasi bilan bir xil bo'lishi uchun uni
      // chizdirib emas, ochiq qiymatlardan hisoblaymiz.
      final p = (t + index / PulsePainter.rings) % 1.0;
      return (
        radius: (size.shortestSide / 2) *
            (1 + (PulsePainter.maxScale - 1) * p),
        alpha: (1 - p) * PulsePainter.peakAlpha,
      );
    }

    test('halqa tugma CHETIDAN boshlanadi', () {
      // Boshida halqa aynan tugma o'lchamida — ya'ni tugma ostida
      // yashiringan va "undan chiqayotgandek" ko'rinadi.
      expect(ring(0, 0).radius, fabSize / 2);
    });

    test('kengayib SO\'NADI', () {
      final a = ring(0.1, 0);
      final b = ring(0.9, 0);
      expect(b.radius, greaterThan(a.radius));
      expect(b.alpha, lessThan(a.alpha));
      expect(ring(0.999, 0).alpha, lessThan(0.01));
    });

    test('eng katta halqa tugmadan ~2 barobar katta', () {
      final maxR = ring(0.999, 0).radius;
      expect(maxR / (fabSize / 2), closeTo(PulsePainter.maxScale, 0.01));
      // Juda katta bo'lsa qo'shni elementlar ustiga chiqadi.
      expect(PulsePainter.maxScale, lessThanOrEqualTo(2.5));
    });

    test('halqalar TENG oraliqda — biri so\'nganda ikkinchisi chiqadi', () {
      const t = 0.2;
      final r0 = ring(t, 0).radius;
      final r1 = ring(t, 1).radius;
      expect(r0, isNot(closeTo(r1, 0.5)));
    });

    test('shouldRepaint faqat KERAK bo\'lganda', () {
      const a = PulsePainter(t: 0.1, color: Colors.red);
      const b = PulsePainter(t: 0.2, color: Colors.red);
      const c = PulsePainter(t: 0.1, color: Colors.green);
      expect(a.shouldRepaint(b), isTrue);
      expect(a.shouldRepaint(c), isTrue);
      expect(a.shouldRepaint(const PulsePainter(t: 0.1, color: Colors.red)),
          isFalse);
    });
  });

  group('FabPulse — ko\'rinmasa TO\'XTAYDI', () {
    Future<ValueNotifier<bool>> pump(WidgetTester tester, bool visible) async {
      final v = ValueNotifier<bool>(visible);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FabPulse(
                visible: v,
                color: Colors.green,
                child: const SizedBox.square(dimension: fabSize),
              ),
            ),
          ),
        ),
      );
      return v;
    }

    testWidgets('ko\'rinsa — kadr rejalashtiriladi', (tester) async {
      await pump(tester, true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'animatsiya yurmayapti');
    });

    testWidgets('ko\'rinmasa — kadr rejalashtirilmaydi', (tester) async {
      await pump(tester, false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'ko\'rinmayotgan tugma bekorga qayta chizilyapti');
    });

    testWidgets('yashirinsa TO\'XTAYDI, qaytsa DAVOM etadi', (tester) async {
      final v = await pump(tester, true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);

      v.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'to\'xtamadi');

      v.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'qayta boshlamadi');
    });

    testWidgets('halqalar TEGINISHNI ushlamaydi', (tester) async {
      var taps = 0;
      final v = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FabPulse(
                visible: v,
                color: Colors.green,
                child: GestureDetector(
                  // ⚠️ Haqiqiy tugma (`_ImageFab`) ham `opaque`. Busiz bo'sh
                  // `SizedBox` hit-test'da UMUMAN qatnashmaydi va test
                  // halqani ayblab, yolg'on yiqiladi.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.square(dimension: fabSize),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(taps, 1, reason: 'halqa bosishni yutib yubordi');
    });
  });
}
