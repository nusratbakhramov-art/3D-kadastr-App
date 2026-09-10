import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/models/capture_guidance.dart';
import 'package:kadastr/features/panorama/models/capture_ring.dart';
import 'package:kadastr/features/panorama/widgets/ring_dial.dart';
import 'package:kadastr/features/panorama/widgets/target_overlay.dart';

/// Capture UX widgetlari.
///
/// Widget testlari piksel solishtirmaydi — ular SINMAYDIGAN da'volarni
/// qotiradi: qaysi indeks qayerda ishlatiladi, qachon qayta chiziladi,
/// bo'sh constraint'da yiqilmaydimi.
void main() {
  Widget host(Widget child, {Size? box}) => MaterialApp(
    home: Scaffold(
      body: box == null
          ? child
          : SizedBox(width: box.width, height: box.height, child: child),
    ),
  );

  TargetSight sight({
    Offset? px,
    GuidanceLevel level = GuidanceLevel.aligned,
    double arrow = 0,
    bool onScreen = true,
    double err = 0.5,
  }) => TargetSight(
    angleErrorDeg: err,
    offsetPixels: px,
    onScreen: onScreen,
    arrowRadians: arrow,
    level: level,
  );

  group('TargetOverlay', () {
    testWidgets('SIZEDBOX SIZ ham chiziladi (Scaffold constraint)', (t) async {
      // Manbadagi to'rtinchi test aynan shunday: hech qanday `SizedBox`
      // yo'q. Bu `size: Size.infinite` ning qo'l bilan berilgan qutidan
      // TASHQARIDA ham xavfsizligini isbotlaydigan yagona test — uni
      // `SizedBox` ga o'rash o'sha qamrovni jimgina o'chiradi.
      await t.pumpWidget(
        host(TargetOverlay(sight: sight(), imageSize: Size.zero, stability: 0)),
      );
      expect(find.byType(TargetOverlay), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('sight null bo‘lsa ham yiqilmaydi', (t) async {
      await t.pumpWidget(
        host(
          const TargetOverlay(
            sight: null,
            imageSize: Size(3000, 4000),
            stability: 0,
          ),
          box: const Size(400, 800),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('imageSize NOL bo‘lsa strelkaga tushadi', (t) async {
      // Kamera hali ochilmagan holat. Masshtab hisoblab bo'lmaydi, ya'ni
      // marker chizib bo'lmaydi — strelka esa chiziladi.
      await t.pumpWidget(
        host(
          TargetOverlay(
            sight: sight(px: const Offset(10, 10)),
            imageSize: Size.zero,
            stability: 0,
          ),
          box: const Size(400, 800),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('TAPNI YUTMAYDI — ostidagi tugma bosiladi', (t) async {
      var tapped = false;
      await t.pumpWidget(
        host(
          Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tapped = true,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              TargetOverlay(
                sight: sight(),
                imageSize: const Size(3000, 4000),
                stability: 0.5,
              ),
            ],
          ),
          box: const Size(400, 800),
        ),
      );
      await t.tapAt(const Offset(200, 400));
      expect(tapped, isTrue, reason: 'IgnorePointer ishlashi kerak');
    });

    testWidgets('shouldRepaint RO‘YXATI aniq', (t) async {
      // `onScreen` KIRADI (u paint'da ishlatilmasa ham — o'zgargani
      // nishonning kadrga kirib-chiqqanini bildiradi).
      // `angleErrorDeg` KIRMAYDI (u sensor tezligida uzluksiz o'zgaradi,
      // vizual natija esa o'zgarmaydi).
      const size = Size(3000, 4000);

      Future<CustomPainter> pump(TargetSight s, double stab) async {
        await t.pumpWidget(
          host(
            TargetOverlay(sight: s, imageSize: size, stability: stab),
            box: const Size(400, 800),
          ),
        );
        return painterIn(t, TargetOverlay);
      }

      final base = await pump(sight(), 0);

      // angleErrorDeg o'zgarishi qayta chizmaydi.
      expect(
        (await pump(sight(err: 9), 0)).shouldRepaint(base),
        isFalse,
        reason: 'angleErrorDeg qayta chizishga sabab BO‘LMASLIGI kerak',
      );

      // onScreen o'zgarishi qayta chizadi.
      expect(
        (await pump(sight(onScreen: false), 0)).shouldRepaint(base),
        isTrue,
        reason: 'onScreen qayta chizishi kerak',
      );

      // stability — to'layotgan halqa shunga tayanadi.
      expect((await pump(sight(), 0.5)).shouldRepaint(base), isTrue);

      // level.
      expect(
        (await pump(sight(level: GuidanceLevel.far), 0)).shouldRepaint(base),
        isTrue,
      );

      // Hech nima o'zgarmasa — qayta chizilmaydi.
      expect((await pump(sight(), 0)).shouldRepaint(base), isFalse);
    });

    group('markerAt — BoxFit.cover shartnomasi', () {
      const screen = Size(400, 800);
      const image = Size(3000, 4000);
      // scale = max(400/3000, 800/4000) = max(0.1333, 0.2) = 0.2
      const scale = 0.2;
      const centre = Offset(200, 400);

      test('MAX masshtab ishlatiladi, min EMAS', () {
        // `min` bo'lsa bu `BoxFit.contain` bo'lardi va nishon
        // ko'rsatayotgan narsasidan siljirdi.
        final at = markerAt(screen, image, const Offset(100, 0), 36)!;
        expect(at.dx, closeTo(centre.dx + 100 * scale, 1e-9));
        // min (0.1333) bilan bu 213.33 bo'lardi.
        expect(at.dx, closeTo(220, 1e-9));
        expect(at.dx, isNot(closeTo(213.33, 0.1)));
      });

      test('markaziy nishon ekran markaziga tushadi', () {
        expect(markerAt(screen, image, Offset.zero, 36), centre);
      });

      test('CHEGARA qamrab oluvchi — aynan chetdagi nishon MARKER', () {
        // margin = 36 + 6 = 42. `p.dx == margin` MARKER berishi kerak.
        // `>` bo'lsa strelka chiqardi.
        const px = (42.0 - 200) / scale; // p.dx aynan 42 bo'ladigan qiymat
        final at = markerAt(screen, image, const Offset(px, 0), 36);
        expect(at, isNotNull, reason: 'aynan chegara — MARKER');
        expect(at!.dx, closeTo(42, 1e-9));

        // Bir piksel tashqarida — strelka.
        const out = (41.0 - 200) / scale;
        expect(markerAt(screen, image, const Offset(out, 0), 36), isNull);
      });

      test('to‘rt tomonning HAMMASI marker radiusini hisobga oladi', () {
        // Faqat chap/tepani tekshirish yarim ishlaydigan shartnoma
        // bo'lardi. Har tomon uchun AYNAN hoshiya chegarasida sinaladi:
        // ichkarisi marker, tashqarisi strelka.
        const m = 42.0; // 36 + 6
        for (final (name, inside, outside) in <(String, Offset, Offset)>[
          // chap: p.dx = 42 / 41
          ('chap', Offset((m - 200) / scale, 0), Offset((41 - 200) / scale, 0)),
          // o'ng: p.dx = 358 / 359
          ('o‘ng', Offset((358 - 200) / scale, 0),
              Offset((359 - 200) / scale, 0)),
          // tepa: p.dy = 42 / 41
          ('tepa', Offset(0, (m - 400) / scale), Offset(0, (41 - 400) / scale)),
          // quyi: p.dy = 758 / 759
          ('quyi', Offset(0, (758 - 400) / scale),
              Offset(0, (759 - 400) / scale)),
        ]) {
          expect(markerAt(screen, image, inside, 36), isNotNull,
              reason: '$name: chegarada MARKER bo‘lishi kerak');
          expect(markerAt(screen, image, outside, 36), isNull,
              reason: '$name: chegaradan tashqarida STRELKA bo‘lishi kerak');
        }
      });

      test('marker RADIUSI chegarani kengaytiradi', () {
        // Katta marker (aligned, 36) kichigidan (far, 17) oldinroq
        // strelkaga aylanadi — aks holda marker ekrandan chiqib ketardi.
        const px = (25.0 - 200) / scale; // p.dx = 25
        expect(markerAt(screen, image, const Offset(px, 0), 17), isNotNull,
            reason: 'margin 23 — 25 ichkarida');
        expect(markerAt(screen, image, const Offset(px, 0), 36), isNull,
            reason: 'margin 42 — 25 tashqarida');
      });

      test('imageSize NOL bo‘lsa `null`', () {
        expect(markerAt(screen, Size.zero, Offset.zero, 36), isNull);
        expect(markerAt(screen, const Size(0, 4000), Offset.zero, 36), isNull);
      });

      test('offsetPixels NULL bo‘lsa `null`', () {
        expect(markerAt(screen, image, null, 36), isNull);
      });

      test('markerRadiusFor daraja bo‘yicha O‘SADI', () {
        expect(markerRadiusFor(GuidanceLevel.far), 17);
        expect(markerRadiusFor(GuidanceLevel.approaching), 24);
        expect(markerRadiusFor(GuidanceLevel.highlighted), 31);
        expect(markerRadiusFor(GuidanceLevel.aligned), 36);
      });
    });

    test('BoxFit.cover masshtabi max(w/iw, h/ih)', () {
      // Shartnomaning arifmetik yarmi. Widget daraxti tomoni (ClipRect +
      // FittedBox(BoxFit.cover) + SizedBox) capture ekranida.
      const screen = Size(400, 800);
      const image = Size(3000, 4000);
      final scale = math.max(
        screen.width / image.width,
        screen.height / image.height,
      );
      expect(scale, closeTo(0.2, 1e-9), reason: '800/4000 = 0.2 > 400/3000');
      // `min` bo'lsa 0.1333 chiqardi va nishon ikki barobar yaqin ko'rinardi.
      expect(
        math.min(screen.width / image.width, screen.height / image.height),
        closeTo(0.1333, 1e-3),
      );
    });
  });

  group('RingDial', () {
    CaptureRing ring() => CaptureRing();

    testWidgets('chiziladi va yiqilmaydi', (t) async {
      await t.pumpWidget(
        host(RingDial(ring: ring(), relativeYaw: 0, activeRow: 0)),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('JUDA KICHIK o‘lchamda yiqilmaydi', (t) async {
      // `outer = shortestSide/2 - 10` — 20 dan kichikda MANFIY bo'ladi.
      for (final s in <double>[0, 1, 10, 19, 20]) {
        await t.pumpWidget(
          host(RingDial(ring: ring(), relativeYaw: 0, size: s)),
        );
        expect(t.takeException(), isNull, reason: 'size=$s');
      }
    });

    testWidgets('halqa NUSXASI saralanmaydi (const ro‘yxat)', (t) async {
      // `ring.rows` — `const List`. Uni joyida saralash `UnsupportedError`
      // tashlardi.
      final r = ring();
      final before = r.rows.map((x) => x.pitchDeg).toList();
      await t.pumpWidget(host(RingDial(ring: r, relativeYaw: 0)));
      expect(t.takeException(), isNull);
      expect(r.rows.map((x) => x.pitchDeg).toList(), before,
          reason: 'qatorlar TARTIBI o‘zgarmasligi kerak');
    });

    group('dialSlots — slot/row ajratmasi', () {
      test('faol qator ROW bo‘yicha aniqlanadi, SLOT bo‘yicha emas', () {
        // Eng oson xato. `defaultRows` da:
        //   slot 0 → row 3 (zenit +90)
        //   slot 1 → row 1 (+45)
        //   slot 2 → row 0 (gorizont) ← faol qator 0 SHU YERDA
        //   slot 3 → row 2 (−45)
        //   slot 4 → row 4 (nadir −90)
        // `slot == activeRow` yozilsa zenit halqasi yonardi.
        final slots = dialSlots(CaptureRing.defaultRows, 100, 0);
        expect(slots.map((s) => s.row).toList(), <int>[3, 1, 0, 2, 4]);

        final activeIdx = slots.indexWhere((s) => s.active);
        expect(activeIdx, 2, reason: 'gorizont uchinchi slotda');
        expect(slots[activeIdx].row, 0);
        // Zenit YONMASLIGI kerak.
        expect(slots[0].active, isFalse);
        expect(slots.where((s) => s.active), hasLength(1));
      });

      test('MANFIY outer da bo‘sh — hech narsa chizilmaydi', () {
        // `shortestSide / 2 - 10` 20 dan kichik o'lchamda manfiy chiqadi.
        // Manfiy radius bilan `drawCircle` istisno TASHLAMAYDI — jimgina
        // g'alati narsa chizadi, ya'ni faqat ko'z bilan ko'rinardi.
        expect(dialSlots(CaptureRing.defaultRows, -5, 0), isEmpty);
        expect(dialSlots(CaptureRing.defaultRows, 0, 0), isEmpty);
        expect(dialSlots(CaptureRing.defaultRows, 0.1, 0), isNotEmpty);
      });

      test('faol qator YO‘Q bo‘lsa hech biri yonmaydi', () {
        final slots = dialSlots(CaptureRing.defaultRows, 100, null);
        expect(slots.every((s) => !s.active), isTrue);
      });

      test('radius 0.45·outer dan outer gacha', () {
        final slots = dialSlots(CaptureRing.defaultRows, 100, null);
        expect(slots.first.radius, closeTo(45, 1e-9));
        expect(slots.last.radius, closeTo(100, 1e-9));
        // Zenit MARKAZGA yaqin — yuqoriga qarash zenitga yaqinlashgani kabi.
        expect(slots.first.row, 3);
      });

      test('BITTA qator — nolga bo‘linish yo‘q', () {
        final slots = dialSlots(
          const <CaptureRow>[CaptureRow(pitchDeg: 0, shotCount: 30)],
          100,
          0,
        );
        expect(slots, hasLength(1));
        expect(slots.first.radius, 100);
        expect(slots.first.active, isTrue);
      });

      test('`rows` NING O‘ZI saralanmaydi', () {
        // `const List` ni joyida saralash `UnsupportedError` tashlardi.
        final rows = CaptureRing.defaultRows;
        final before = rows.map((r) => r.pitchDeg).toList();
        dialSlots(rows, 100, 0);
        expect(rows.map((r) => r.pitchDeg).toList(), before);
      });

      test('BIR XIL pitch‘li ikki qator ham to‘g‘ri indekslanadi', () {
        // Nusxani saralab `indexOf` qilish bu yerda NOTO'G'RI indeks
        // berardi — ikkala qator ham birinchisiga ishora qilardi.
        const rows = <CaptureRow>[
          CaptureRow(pitchDeg: 0, shotCount: 30),
          CaptureRow(pitchDeg: 0, shotCount: 20),
        ];
        final slots = dialSlots(rows, 100, 1);
        expect(slots.map((s) => s.row).toSet(), <int>{0, 1},
            reason: 'ikki xil indeks bo‘lishi kerak');
        expect(slots.where((s) => s.active), hasLength(1));
        expect(slots.firstWhere((s) => s.active).row, 1);
      });
    });

    test('SLOT va ROW adashtirilmaydi', () {
      // Eng oson xato: `slot == activeRow`. `defaultRows` da qatorlar
      // pitch bo'yicha kamayish tartibida joylashadi:
      //   slot 0 → row 3 (zenit,  +90)
      //   slot 1 → row 1 (+45)
      //   slot 2 → row 0 (gorizont, 0)   ← faol qator 0 SHU YERDA
      //   slot 3 → row 2 (−45)
      //   slot 4 → row 4 (nadir, −90)
      // Ya'ni `slot == 0` deb yozilsa zenit halqasi yonardi.
      final rows = CaptureRing.defaultRows;
      final byPitch = <int>[for (int i = 0; i < rows.length; i++) i]
        ..sort((a, b) => rows[b].pitchDeg.compareTo(rows[a].pitchDeg));
      expect(byPitch, <int>[3, 1, 0, 2, 4]);
      expect(byPitch.indexOf(0), 2, reason: 'gorizont uchinchi slotda');
      expect(byPitch[0], 3, reason: 'birinchi slot — zenit');
    });

    test('radius slot bo‘yicha, 0.45 dan 1.0 gacha', () {
      double radius(int slot, int n, double outer) =>
          n == 1 ? outer : outer * (0.45 + 0.55 * slot / (n - 1));
      expect(radius(0, 5, 100), closeTo(45, 1e-9));
      expect(radius(4, 5, 100), closeTo(100, 1e-9));
      // Bitta qator — bo'linish 0 ga tushmasligi kerak.
      expect(radius(0, 1, 100), 100);
    });

    testWidgets('YANGI KADR olinganda qayta chiziladi', (t) async {
      // ⚠️ MANBADAGI XATONING TESTI. Manbada shart
      // `old.ring.takenCount != ring.takenCount` edi va capture ekrani
      // BITTA o'zgaruvchan halqa bergani uchun u hech qachon rost
      // bo'lmasdi — ya'ni yangi yashil nuqta aynan zatvor ochilgan
      // lahzada (telefon qimirlamay turganda, yaw ham qotgan) ko'rinmasdi.
      final r = ring();

      Future<CustomPainter> pump() async {
        await t.pumpWidget(
          host(RingDial(ring: r, relativeYaw: 0, activeRow: 0)),
        );
        return painterIn(t, RingDial);
      }

      final before = await pump();
      r.record(const ShotId(0, 0), 0); // halqa o'zgardi, AYNI nusxa
      final after = await pump();

      expect(
        after.shouldRepaint(before),
        isTrue,
        reason: 'yangi yashil nuqta darhol ko‘rinishi kerak',
      );
    });

    testWidgets('yaw yoki faol qator o‘zgarsa ham qayta chiziladi', (t) async {
      final r = ring();
      Future<CustomPainter> pump(double yaw, int? row) async {
        await t.pumpWidget(
          host(RingDial(ring: r, relativeYaw: yaw, activeRow: row)),
        );
        return painterIn(t, RingDial);
      }

      final a = await pump(0, 0);
      expect((await pump(1, 0)).shouldRepaint(a), isTrue);
      expect((await pump(0, 1)).shouldRepaint(a), isTrue);
      expect(
        (await pump(0, 0)).shouldRepaint(a),
        isFalse,
        reason: 'hech nima o‘zgarmasa qayta chizilmaydi',
      );
    });
  });
}

/// Pumped daraxtdan [CustomPainter] ni oladi.
///
/// `build(context)` ni qo'lda chaqirishdan ko'ra ishonchli: widget haqiqiy
/// daraxtda qurilgan bo'ladi va soxta kontekst kerak emas.
CustomPainter painterIn(WidgetTester t, Type of) => t
    .widgetList<CustomPaint>(
      find.descendant(of: find.byType(of), matching: find.byType(CustomPaint)),
    )
    .first
    .painter!;
