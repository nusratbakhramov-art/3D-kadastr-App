import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/core/i18n/app_translations.dart';
import 'package:kadastr/features/panorama/data/camera_guard.dart';
import 'package:kadastr/features/panorama/data/heading_source.dart';
import 'package:kadastr/features/panorama/models/pano_progress.dart';
import 'package:kadastr/features/panorama/screens/pano_capture_screen.dart';

/// Capture ekrani.
///
/// Kamera va sensorlarsiz tekshiriladigan qismlar: ekspozitsiya
/// o'rtachalash, tasvir o'lchami normallashtirish, i18n kalitlari va
/// kamera band bo'lgandagi yo'l.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('atShutter — ekspozitsiyani QAMRAB olish', () {
    const before = DeviceAim(yawDeg: 10, pitchDeg: 20, rollDeg: 2);

    test('ikki o‘qish o‘rtachalanadi', () {
      // Zatvorni ochgan yo'nalish undan OLDIN o'qilgan, `takePicture` esa
      // bir necha yuz millisekundda qaytadi — telefon shu vaqtda
      // qimirlaydi. O'rtachalash ekspozitsiyani qamrab oladi.
      const after = DeviceAim(yawDeg: 20, pitchDeg: 30, rollDeg: 4);
      final m = atShutter(before, after);
      expect(m.yawDeg, closeTo(15, 1e-9));
      expect(m.pitchDeg, closeTo(25, 1e-9));
      expect(m.rollDeg, closeTo(3, 1e-9));
    });

    test('359/0 CHEGARASIDA 180 ga qarab qolmaydi', () {
      // Bu o'rtachalashning butun mohiyati. Oddiy o'rtacha bu yerda
      // 180 berardi va kadr sferaning QARAMA-QARSHI tomoniga tushardi.
      const a = DeviceAim(yawDeg: 359, pitchDeg: 0);
      const b = DeviceAim(yawDeg: 1, pitchDeg: 0);
      final m = atShutter(a, b);
      expect(m.yawDeg, closeTo(0, 1e-9));
      expect(m.yawDeg, isNot(closeTo(180, 1)));

      // Teskari yo'nalish ham.
      final m2 = atShutter(b, a);
      expect(m2.yawDeg, closeTo(0, 1e-9));
    });

    test('natija 0..360 dan chiqmaydi', () {
      for (final (x, y) in <(double, double)>[
        (350, 10),
        (10, 350),
        (0, 359),
        (180, 181),
      ]) {
        final m = atShutter(
          DeviceAim(yawDeg: x, pitchDeg: 0),
          DeviceAim(yawDeg: y, pitchDeg: 0),
        );
        expect(m.yawDeg, inInclusiveRange(0, 360), reason: '$x → $y');
      }
    });

    test('after NULL bo‘lsa before qaytadi', () {
      expect(atShutter(before, null), before);
    });

    test('steady BEFORE dan olinadi', () {
      // Zatvor ochilgan payt qimirlamagan bo'lsa, keyin qimirlagani
      // kadrni bekor qilmaydi.
      const a = DeviceAim(yawDeg: 0, pitchDeg: 0, steady: true);
      const b = DeviceAim(yawDeg: 1, pitchDeg: 0);
      expect(atShutter(a, b).steady, isTrue);
    });

    test('xom qurilma roll‘i ham o‘rtachalanadi', () {
      const a = DeviceAim(yawDeg: 0, pitchDeg: 0, rawDeviceRollDeg: 170);
      const b = DeviceAim(yawDeg: 0, pitchDeg: 0, rawDeviceRollDeg: 174);
      expect(
        atShutter(a, b).rawDeviceRollDeg,
        closeTo(172, 1e-9),
      );
    });
  });

  group('i18n kalitlari', () {
    late Map<String, dynamic> uz;

    setUpAll(() {
      final raw = File('assets/i18n/bundle.json').readAsStringSync();
      uz = (jsonDecode(raw) as Map<String, dynamic>)['locales']['uz']
          as Map<String, dynamic>;
    });

    test('HAR BOSQICH uchun kalit bor', () {
      // ⚠️ Bosqich nomi kalitga DINAMIK qo'shiladi
      // (`bozor.pano.stitch.${phase.name}`), ya'ni yetishmagan kalit
      // kompilyatsiya xatosi bermaydi — ekranda XOM KALIT ko'rinadi.
      for (final p in StitchPhase.values) {
        expect(
          uz.containsKey('bozor.pano.stitch.${p.name}'),
          isTrue,
          reason: '${p.name} bosqichi uchun kalit yo‘q',
        );
      }
    });

    test('stitchLabelKey HAR BOSQICH uchun MAVJUD kalit beradi', () {
      // ⚠️ Bu ekranning yagona DINAMIK kaliti — yetishmasa kompilyatsiya
      // xatosi bermaydi, ekranda xom kalit ko'rinadi.
      for (final ph in StitchPhase.values) {
        final k = stitchLabelKey(ph);
        expect(k, 'bozor.pano.stitch.${ph.name}');
        expect(uz.containsKey(k), isTrue, reason: k);
      }
      // `null` — dekod bosqichiga tushadi (tikish boshlanmagan).
      expect(stitchLabelKey(null), 'bozor.pano.stitch.decode');
      expect(uz.containsKey(stitchLabelKey(null)), isTrue);
    });

    test('kodda ishlatilgan HAMMA kalit bundle‘da bor', () {
      final src = File(
        'lib/features/panorama/screens/pano_capture_screen.dart',
      ).readAsStringSync();
      final used = RegExp(r"'(bozor\.pano\.[a-z._]+)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toSet();
      expect(used, isNotEmpty);
      for (final k in used) {
        expect(uz.containsKey(k), isTrue, reason: '$k bundle‘da yo‘q');
      }
    });

    test('uchala tilda BIR XIL kalitlar', () {
      final raw = File('assets/i18n/bundle.json').readAsStringSync();
      final locales =
          (jsonDecode(raw) as Map<String, dynamic>)['locales']
              as Map<String, dynamic>;
      final sets = <String, Set<String>>{
        for (final e in locales.entries)
          e.key: (e.value as Map<String, dynamic>).keys.toSet(),
      };
      final pano = <String, Set<String>>{
        for (final e in sets.entries)
          e.key: e.value.where((k) => k.startsWith('bozor.pano.')).toSet(),
      };
      // ASOSIY da'vo: uchala til bir xil kalit to'plamiga ega. Bittasida
      // kalit yetishmasa o'sha tilda XOM KALIT ko'rinardi.
      expect(pano['uz'], pano['ru']);
      expect(pano['uz'], pano['en']);
      // Son o'zgarishi NORMAL, lekin O'YLAMASDAN o'zgarmasligi kerak —
      // yangi kalit qo'shilsa uchala tilga ham qo'shilgani tekshirilsin.
      // 25 → 30: `bozor.pano.resume.*` (5 ta) — tashlab ketilgan
      // suratga olishni yig'ishni taklif qilish (`0dac253` porti).
      // 30 → 32: `bozor.pano.view.*` (2 ta) — sferadagi ko'ruvchi.
      // 32 → 46: `bozor.pano.tour.*` (14 ta) — 360° house tour.
      // 46 → 49: `bozor.pano.view.err_{missing,network,decode}` —
      // nosozlik SABABI. Ilgari uch xil xato bitta matn berardi va
      // qurilmadagi xabardan nima bo'lganini aniqlab bo'lmasdi.
      expect(pano['uz'], hasLength(49));
    });

    test('tarjimalar BO‘SH emas va kalitning o‘zi emas', () {
      // `tr()` kalit topilmasa KALITNING O'ZINI qaytaradi — ya'ni
      // bo'sh yoki kalitga teng qiymat gapni yashiradi.
      for (final k in uz.keys.where((k) => k.startsWith('bozor.pano.'))) {
        expect((uz[k] as String).trim(), isNotEmpty, reason: k);
        expect(uz[k], isNot(k), reason: k);
      }
    });
  });

  group('kamera BAND bo‘lganda', () {
    setUp(() => CameraGuard.reset('test'));
    tearDown(() => CameraGuard.reset('test'));

    testWidgets('ekran ochilmaydi, xato ko‘rsatiladi', (t) async {
      // ⚠️ IJARA KAMERANI OCHISHDAN OLDIN so'raladi — ya'ni bu yo'l
      // haqiqiy kamerasiz ham yuriladi.
      expect(CameraGuard.acquire(CameraGuard.lidar), isTrue);

      await t.pumpWidget(const MaterialApp(home: PanoCaptureScreen()));
      await t.pump();

      // Guard hali `lidar` qo'lida — panorama uni TORTIB OLMAGAN.
      expect(CameraGuard.holder, CameraGuard.lidar);
      expect(t.takeException(), isNull);
      // Xato matni ko'rinadi (bundle yuklanmagani uchun xom kalit).
      expect(
        find.textContaining('camera_busy'),
        findsOneWidget,
        reason: 'kamera band xabari ko‘rinishi kerak',
      );
    });

    testWidgets('yopilganda IJARA bo‘shaydi', (t) async {
      await t.pumpWidget(const MaterialApp(home: PanoCaptureScreen()));
      await t.pump();
      // Ekran ijarani oldi (kamera ochilmasa ham).
      expect(CameraGuard.holder, CameraGuard.panorama);

      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pump();
      expect(
        CameraGuard.isFree,
        isTrue,
        reason: 'ijara qotib qolmasligi kerak',
      );
    });
  });

  test('tr() topilmagan kalitda KALITNI qaytaradi', () {
    // Yuqoridagi widget testi shunga tayanadi.
    expect(tr(const Locale('uz'), 'yo.q.kalit'), 'yo.q.kalit');
  });
}
