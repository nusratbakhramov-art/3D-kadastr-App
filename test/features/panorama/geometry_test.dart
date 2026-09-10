import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/stitch/geometry.dart';

/// Ekvirektangulyar tuval geometriyasi.
///
/// Eng muhim testlar «to'g'ri hisoblaydimi» degan savolga emas, IKKI
/// KELISHUV BIR-BIRIGA MOS KELADIMI degan savolga javob beradi:
/// [footprint] kadr tuvalning qaysi qismiga tushishini OLDINDAN aytadi,
/// proyektor esa o'sha qismni haqiqatan hisoblaydi. Ikkisi ajralib ketsa
/// hech qanday xato chiqmaydi — kadr cheti jimgina qirqiladi va chokda
/// qora chiziq qoladi.
void main() {
  // Reja bo'yicha chiqish 3072×1536, kadr 3840×2160 (4K), FOV 67.3°.
  const canvasW = 3072;
  const canvasH = 1536;
  const fw = 3840;
  const fh = 2160;
  final focal = focalPx(fw, fh, 67.3);

  group('tuval ↔ burchak kelishuvi', () {
    test('qator 0 — ZENIT, oxirgi qator — NADIR', () {
      // Teskari bo'lsa butun panorama tepa-tekis aylanadi.
      expect(latOfRow(0, canvasH), greaterThan(0));
      expect(latOfRow(canvasH - 1, canvasH), lessThan(0));
      expect(latOfRow(0, canvasH), closeTo(math.pi / 2, 0.002));
      expect(latOfRow(canvasH - 1, canvasH), closeTo(-math.pi / 2, 0.002));
    });

    test('markaziy qator gorizont', () {
      // 1536 qatorda aniq markaz yo'q; 767 va 768 nolni o'rab turadi.
      expect(latOfRow(767, canvasH), greaterThan(0));
      expect(latOfRow(768, canvasH), lessThan(0));
      expect(latOfRow(767, canvasH).abs(), closeTo(0.001, 0.001));
    });

    test('YARIM PIKSEL markazi ishlatiladi', () {
      // `+0.5` tashlab ketilsa qator 0 aynan π/2 ga tushardi, ya'ni
      // qutbning o'zi — u yerda uzunlik aniqlanmagan.
      expect(latOfRow(0, canvasH), lessThan(math.pi / 2));
      expect(lonOfCol(0, canvasW), greaterThan(0));
      expect(lonOfCol(0, canvasW), closeTo(math.pi / canvasW, 1e-9));
    });

    test('uzunlik 0..2π ni to‘liq qamraydi', () {
      expect(lonOfCol(0, canvasW), closeTo(0, 0.002));
      expect(lonOfCol(canvasW - 1, canvasW), closeTo(2 * math.pi, 0.003));
    });

    test('rowOfLat / colOfLon aynan teskari', () {
      for (final v in <int>[0, 1, 383, 767, 768, 1535]) {
        expect(rowOfLat(latOfRow(v, canvasH), canvasH), closeTo(v, 1e-9));
      }
      for (final u in <int>[0, 1, 1000, 3071]) {
        expect(colOfLon(lonOfCol(u, canvasW), canvasW), closeTo(u, 1e-9));
      }
    });
  });

  group('directionOf', () {
    test('birlik vektor qaytaradi', () {
      for (final lat in <double>[-1.5, -0.7, 0, 0.7, 1.5]) {
        for (final lon in <double>[0, 1, 3, 5, 6.2]) {
          final d = directionOf(lat, lon);
          final m = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
          expect(m, closeTo(1, 1e-12));
        }
      }
    });

    test('Y VERTIKAL o‘q — X yoki Z emas', () {
      // Almashtirish 90° burilish beradi va hech qanday xato chiqarmaydi.
      final up = directionOf(math.pi / 2, 0);
      expect(up[1], closeTo(1, 1e-12));
      expect(up[0], closeTo(0, 1e-12));
      expect(up[2], closeTo(0, 1e-12));
    });

    test('lon = 0 da +Z ga qaraydi', () {
      final d = directionOf(0, 0);
      expect(d[2], closeTo(1, 1e-12));
      expect(d[0], closeTo(0, 1e-12));
    });

    test('lon = π/2 da +X ga qaraydi', () {
      final d = directionOf(0, math.pi / 2);
      expect(d[0], closeTo(1, 1e-12));
      expect(d[2], closeTo(0, 1e-12));
    });
  });

  group('frameCentre', () {
    test('birlik matritsa lon=0, lat=0 beradi', () {
      final r = rotationMatrix(0, 0, 0);
      final c = frameCentre(r);
      expect(c.lon, closeTo(0, 1e-12));
      expect(c.lat, closeTo(0, 1e-12));
    });

    test('rotatsiya matritsasi bilan mos ishlaydi', () {
      // `frameCentre` kameraning +Z o'qini dunyoga o'girishi kerak, ya'ni
      // matritsani (0,0,1) ga qo'llash bilan bir xil natija.
      for (final psi in <double>[0, 0.4, -1.1]) {
        for (final theta in <double>[0, 0.3, -0.6]) {
          final r = rotationMatrix(psi, theta, 0);
          final c = frameCentre(r);
          final d = directionOf(c.lat, c.lon);
          // Matritsaning uchinchi USTUNI = kamera +Z ning dunyodagi tasviri.
          expect(d[0], closeTo(r[2], 1e-9));
          expect(d[1], closeTo(r[5], 1e-9));
          expect(d[2], closeTo(r[8], 1e-9));
        }
      }
    });

    test('asin argumenti QISILADI — NaN chiqmaydi', () {
      // Suzuvchi nuqta xatosi r[5] ni 1.0000001 qilib qo'yishi mumkin;
      // qisilmasa `asin` NaN beradi va butun iz NaN bo'ladi.
      final c = frameCentre(<double>[0, 0, 0, 0, 0, 1.0000001, 0, 0, 1]);
      expect(c.lat.isNaN, isFalse);
      expect(c.lat, closeTo(math.pi / 2, 1e-6));
    });
  });

  group('capRadius', () {
    test('4K kadr 67.3° FOV da ~38.5° qalpoq qamraydi', () {
      final r = capRadius(fw, fh, focal);
      expect(r / (math.pi / 180), closeTo(38.47, 0.05));
    });

    test('zaxira QO‘SHILADI, ayrilmaydi', () {
      // Iz kadrdan kichik bo'lsa cheti qirqiladi va chokda qora chiziq
      // qoladi — katta bo'lsa faqat bir necha ortiqcha piksel hisoblanadi.
      final withM = capRadius(fw, fh, focal, marginRad: 0.02);
      final noM = capRadius(fw, fh, focal, marginRad: 0);
      expect(withM, greaterThan(noM));
      expect(withM - noM, closeTo(0.02, 1e-12));
    });

    test('uzun fokus — kichik qalpoq', () {
      expect(
        capRadius(fw, fh, focal * 2, marginRad: 0),
        lessThan(capRadius(fw, fh, focal, marginRad: 0)),
      );
    });
  });

  group('footprint', () {
    Roi at(double latDeg, [double lonRad = 0]) => footprint(
      lon: lonRad,
      lat: latDeg * math.pi / 180,
      fw: fw,
      fh: fh,
      focal: focal,
      canvasW: canvasW,
      canvasH: canvasH,
    );

    test('gorizont kadri tuvalning kichik qismini oladi', () {
      final roi = at(0);
      // halfLon = 38.47° → yarim en ≈ 0.1068 · 3072 + 1 ≈ 329.
      expect(roi.width, closeTo(659, 3));
      expect(roi.width, lessThan(canvasW));
      // Vertikal: ±38.47° → 76.94° / 180° · 1536 ≈ 656.
      expect(roi.height, closeTo(658, 4));
    });

    test('QUTB kadri butun aylanani oladi', () {
      // Buni hisobga olmaslik qutb kadrini tor tasmaga qisib qo'yardi —
      // aynan u yopishi kerak bo'lgan joyni.
      expect(at(90).width, canvasW);
      expect(at(-90).width, canvasW);
      expect(at(90).v0, 0, reason: 'zenitdan boshlanadi');
    });

    test('±45 qatori HALI to‘liq en EMAS', () {
      // 45 + 38.47 = 83.47 < 90, ya'ni qalpoq qutbni o'ramaydi. Agar
      // bo'sag'a xato bo'lsa bu qator ham butun tuvalga cho'zilib ketardi
      // va har kadr 4.7 M piksel hisoblardi — 76 kadrda bajarilmaydi.
      expect(at(45).width, lessThan(canvasW));
      expect(at(-45).width, lessThan(canvasW));
    });

    test('51.5° dan keyin en to‘liq bo‘ladi', () {
      // Bo'sag'a: |lat| + radius >= π/2, ya'ni |lat| >= 90 - 38.47 = 51.53.
      expect(at(51).width, lessThan(canvasW));
      expect(at(52).width, canvasW);
    });

    test('yuqori kenglikda en O‘SADI', () {
      expect(at(30).width, greaterThan(at(0).width));
      expect(at(45).width, greaterThan(at(30).width));
    });

    test('chokka qaragan kadr MANFIY u0 beradi (qisilmaydi)', () {
      // Bu izning MOHIYATI: u0 manfiy bo'lishi va o'rash keyinroq hal
      // qilinishi kerak. Bu yerda qisib qo'yish kadrni yarmiga bo'lardi.
      final roi = at(0, 0);
      expect(roi.u0, lessThan(0));
      expect(roi.u0 + roi.width, greaterThan(0));
    });

    test('tuval o‘ng chetida u0 + width tuvaldan OSHADI', () {
      final roi = at(0, 2 * math.pi - 0.01);
      expect(roi.u0 + roi.width, greaterThan(canvasW));
    });

    test('en HECH QACHON tuvaldan oshmaydi', () {
      // Bu `columnBlocks` ning ikkitadan ko'p blok qaytarmasligini
      // kafolatlaydi.
      for (final lat in <double>[-90, -52, -45, 0, 45, 52, 90]) {
        for (final lon in <double>[0, 1, 3, 5, 6.28]) {
          expect(at(lat, lon).width, lessThanOrEqualTo(canvasW));
        }
      }
    });

    test('qutb shoxi `s >= 1` ga EKVIVALENT (o‘lchangan)', () {
      // Bu test qutb shartining nima qilmasligini qotiradi: u qutb
      // kadrlarini qutqarayotgani ROST EMAS — ikki shart bir xil.
      // Shart nima uchun saqlanganini keyingi test ko‘rsatadi.
      final radius = capRadius(fw, fh, focal);
      var disagree = 0;
      for (var i = -900; i <= 900; i++) {
        final lat = i / 1000.0 * math.pi / 2;
        final cosLat = math.cos(lat);
        final fast = lat.abs() + radius >= math.pi / 2 || cosLat <= 1e-6;
        final slow = math.sin(radius) / cosLat >= 1;
        if (fast != slow) disagree++;
      }
      expect(disagree, 0, reason: '1801 kenglikda ikki shart bir xil');
    });

    test('qutb shoxi NOL ENLI izni oldini oladi (yagona haqiqiy roli)', () {
      // `radius == 0` va `lat == ±90°`: `else` shoxi `s = 0` berib
      // `halfLon = 0` qilardi, ya'ni iz eni 3 piksel bo'lib qolardi va
      // qutb kadri tuvalga deyarli tushmasdi.
      final roi = footprint(
        lon: 0,
        lat: math.pi / 2,
        fw: fw,
        fh: fh,
        focal: double.infinity, // radius = atan(0) + 0 = 0
        canvasW: canvasW,
        canvasH: canvasH,
        marginRad: 0,
      );
      expect(roi.width, canvasW, reason: 'xavfsiz ortiqcha baho');
    });

    test('v0/v1 tuval ichida qoladi', () {
      for (final lat in <double>[-90, -60, 0, 60, 90]) {
        final roi = at(lat);
        expect(roi.v0, inInclusiveRange(0, canvasH - 1));
        expect(roi.v0 + roi.height, lessThanOrEqualTo(canvasH));
        expect(roi.height, greaterThan(0));
      }
    });

    test('iz PROYEKSIYA bilan mos — kadr markazi iz ichida', () {
      // Ikki kelishuvni bog'laydigan test. Kadr markazining tuvaldagi
      // o'rni izning ichida bo'lishi SHART, aks holda proyektor kadrning
      // eng muhim (eng o'tkir) qismini umuman hisoblamaydi.
      for (final latDeg in <double>[-45, -20, 0, 20, 45]) {
        final lat = latDeg * math.pi / 180;
        const lon = 2.0;
        final roi = at(latDeg, lon);
        final double vc = rowOfLat(lat, canvasH);
        final double uc = colOfLon(lon, canvasW);
        expect(
          vc,
          inInclusiveRange(roi.v0.toDouble(), (roi.v0 + roi.height).toDouble()),
          reason: '$latDeg°: markaz qatori iz tashqarisida',
        );
        expect(
          uc,
          inInclusiveRange(roi.u0.toDouble(), (roi.u0 + roi.width).toDouble()),
          reason: '$latDeg°: markaz ustuni iz tashqarisida',
        );
      }
    });

    test('iz kadr BURCHAKLARINI ham qamraydi', () {
      // Markaz yetmaydi: kadr to'rtburchak, qalpoq esa diagonal bo'yicha
      // o'lchanadi. Kadrning eng chetki nuri ham iz ichida bo'lishi kerak.
      const lon = 2.0;
      final roi = at(0, lon);
      final r = rotationMatrix(0, 0, 0);
      expect(r, isNotNull);
      final double radius = capRadius(fw, fh, focal, marginRad: 0);
      // Eng yuqori va eng past nur.
      expect(rowOfLat(radius, canvasH), greaterThanOrEqualTo(roi.v0 - 1.0));
      expect(
        rowOfLat(-radius, canvasH),
        lessThanOrEqualTo(roi.v0 + roi.height + 1.0),
      );
      final double uc = colOfLon(lon, canvasW);
      final double halfU = radius / (2 * math.pi) * canvasW;
      expect(uc - halfU, greaterThanOrEqualTo(roi.u0 - 1.0));
      expect(uc + halfU, lessThanOrEqualTo(roi.u0 + roi.width + 1.0));
    });
  });

  group('columnBlocks', () {
    test('o‘rashsiz iz BITTA blok', () {
      final b = columnBlocks(const Roi(100, 0, 50, 10), 3072);
      expect(b, <(int, int, int)>[(0, 100, 50)]);
    });

    test('MANFIY u0 ikki blokka bo‘linadi', () {
      // -10..39 → tuvalning 3062..3071 va 0..39 ustunlari.
      final b = columnBlocks(const Roi(-10, 0, 50, 10), 3072);
      expect(b, <(int, int, int)>[(0, 3062, 10), (10, 0, 40)]);
    });

    test('O‘NG chetdan oshgan iz ham ikki blok', () {
      final b = columnBlocks(const Roi(3050, 0, 50, 10), 3072);
      expect(b, <(int, int, int)>[(0, 3050, 22), (22, 0, 28)]);
    });

    test('to‘liq en BITTA blok (aynan tuval)', () {
      final b = columnBlocks(const Roi(0, 0, 3072, 10), 3072);
      expect(b, <(int, int, int)>[(0, 0, 3072)]);
    });

    test('to‘liq en, siljigan boshlanish — ikki blok', () {
      final b = columnBlocks(const Roi(1000, 0, 3072, 10), 3072);
      expect(b, hasLength(2));
      expect(b[0], (0, 1000, 2072));
      expect(b[1], (2072, 0, 1000));
    });

    test('bloklar izni TO‘LIQ va bir marta qoplaydi', () {
      for (final u0 in <int>[-3000, -10, 0, 5, 1000, 3060, 3072, 6000]) {
        for (final w in <int>[1, 50, 3000, 3072]) {
          final roi = Roi(u0, 0, w, 4);
          final b = columnBlocks(roi, 3072);
          expect(
            b.fold<int>(0, (s, x) => s + x.$3),
            w,
            reason: 'u0=$u0 w=$w: jami run izning eniga teng bo‘lishi kerak',
          );
          expect(b.length, lessThanOrEqualTo(2), reason: 'u0=$u0 w=$w');
          // Har blok tuval ichida.
          for (final (src, dst, run) in b) {
            expect(dst, inInclusiveRange(0, 3071));
            expect(dst + run, lessThanOrEqualTo(3072));
            expect(src + run, lessThanOrEqualTo(w));
          }
        }
      }
    });

    test('ENIDAN OSHGAN iz assert bilan to‘xtatiladi', () {
      // Nosozlik «uch blok» bo'lib KO'RINMAYDI: tsikl baribir ikki blok
      // qaytaradi, lekin ikkinchisi birinchisining ustunlarini QAYTA
      // YOZADI. Shuning uchun shart enning o'ziga qo'yilgan.
      expect(
        () => columnBlocks(const Roi(0, 0, 5000, 4), 3072),
        throwsA(isA<AssertionError>()),
      );
      // Aynan tuval eni — hali ruxsat etilgan.
      expect(columnBlocks(const Roi(0, 0, 3072, 4), 3072), hasLength(1));
    });

    test('Dart `%` si manfiy bo‘lmagan natija beradi — `remainder` EMAS', () {
      // `columnBlocks` shunga tayanadi. `%` ni `.remainder()` ga
      // almashtirish manfiy `dstX` berib tuval tashqarisiga yozardi.
      expect((-10) % 3072, 3062);
      expect((-3000) % 3072, 72);
      expect((-10).remainder(3072), -10, reason: 'C uslubi — BU YERDA BUZADI');
    });

    test('nol enli iz bo‘sh ro‘yxat', () {
      expect(columnBlocks(const Roi(10, 0, 0, 4), 3072), isEmpty);
      expect(const Roi(10, 0, 0, 4).isEmpty, isTrue);
    });
  });
}
