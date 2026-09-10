import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/panorama/math/rotation.dart';
import 'package:kadastr/features/panorama/stitch/geometry.dart';
import 'package:kadastr/features/panorama/stitch/project.dart';

/// Proyeksiya — kadrni ekvirektangulyar tuvalga qo'yish.
///
/// Eng kuchli test — AYLANMA YO'L: sun'iy sfera yasaladi, undan kadr
/// «suratga olinadi», so'ng o'sha kadr tuvalga qaytarib qo'yiladi va asl
/// sfera bilan solishtiriladi. Bu bir-biriga bog'liq to'rt kelishuvni
/// (rotatsiya, tuval, kamera nuri, teskari xaritalash) BIR VAQTDA
/// tekshiradi: ularning biri buzilsa aylanma yo'l yopilmaydi.
void main() {
  const canvasW = 256;
  const canvasH = 128;
  const fw = 64;
  const fh = 64;
  final focal = focalPx(fw, fh, 60);

  FrameMap mapAt(double psi, double theta, {bool wta = true}) => buildFrameMap(
    rotation: rotationMatrix(psi, theta, 0),
    frameW: fw,
    frameH: fh,
    focal: focal,
    canvasW: canvasW,
    canvasH: canvasH,
    winnerTakeAll: wta,
  );

  group('taperWeight — tor og‘irlik', () {
    test('markazda 1, chetga qarab tushadi', () {
      expect(taperWeight(32, 32, 32, 32), closeTo(1, 1e-12));
      expect(taperWeight(16, 32, 32, 32), closeTo(0.5, 1e-12));
      expect(taperWeight(16, 16, 32, 32), closeTo(0.25, 1e-12));
    });

    test('AYNAN chekkada pol qo‘llanadi — nol EMAS', () {
      // `x == 0` da `wx = 0`, ya'ni og'irlik nol bo'lardi. Yutuvchi
      // QAT'IY `>` bilan tanlanadi, demak nol og'irlikli piksel HECH
      // KIM tomonidan olinmaydi va qora qoladi — keyin detal o'tishi
      // uni QORA SOCH TOLASI bo'lib panoramaga ko'taradi (manbada
      // ~20 000 ta, 224 darajaga chuqur).
      expect(taperWeight(0, 32, 32, 32), kCoveredFloor);
      expect(taperWeight(64, 32, 32, 32), kCoveredFloor);
      expect(taperWeight(32, 0, 32, 32), kCoveredFloor);
      expect(taperWeight(0, 0, 32, 32), kCoveredFloor);
    });

    test('juda kichik, lekin nolmas og‘irlik ham polga ko‘tariladi', () {
      // `t = 1e-12` — nol emas, lekin float32 da yo'qoladi.
      final t = taperWeight(32 - 32 * (1 - 1e-12), 32, 32, 32);
      expect(t, greaterThanOrEqualTo(kCoveredFloor));
    });

    test('winnerTakeAll LINEAR, aks holda daraja', () {
      expect(taperWeight(16, 32, 32, 32), closeTo(0.5, 1e-12));
      expect(
        taperWeight(16, 32, 32, 32, winnerTakeAll: false, blendPower: 16),
        closeTo(math.pow(0.5, 16), 1e-12),
      );
      expect(
        taperWeight(16, 32, 32, 32, winnerTakeAll: false, blendPower: 1),
        closeTo(0.5, 1e-12),
        reason: 'blendPower 1 — darajaga ko‘tarilmaydi',
      );
    });
  });

  group('buildFrameMap — xarita', () {
    test('izning ichida namuna BOR', () {
      final m = mapAt(0, 0);
      final covered = m.valid.where((v) => v > 0).length;
      expect(covered, greaterThan(0));
      // Iz kadr qalpog'ini o'raydi, ya'ni burchaklarda namuna yo'q —
      // hammasi qoplangan bo'lsa iz juda tor demakdir.
      expect(covered, lessThan(m.length));
    });

    test('namunasiz piksel `-1` bilan belgilanadi', () {
      final m = mapAt(0, 0);
      for (int i = 0; i < m.length; i++) {
        if (m.valid[i] == 0) {
          expect(m.mapX[i], -1);
          expect(m.mapY[i], -1);
          expect(m.weight[i], 0);
        }
      }
    });

    test('xarita KADR ichida qoladi', () {
      final m = mapAt(0.7, -0.3);
      for (int i = 0; i < m.length; i++) {
        if (m.valid[i] > 0) {
          expect(m.mapX[i], inInclusiveRange(0, fw - 1));
          expect(m.mapY[i], inInclusiveRange(0, fh - 1));
        }
      }
    });

    test('LINZA ORQASI kesiladi', () {
      // Kadr markazidan 180° qarama-qarshi tomonda hech narsa bo'lmasligi
      // kerak. Kesilmasa kadr sferaning teskari tomoniga «arvoh» bo'lib
      // tushardi.
      final m = mapAt(0, 0);
      final centre = frameCentre(rotationMatrix(0, 0, 0));
      for (int j = 0; j < m.roi.height; j++) {
        for (int i = 0; i < m.roi.width; i++) {
          if (m.valid[j * m.roi.width + i] == 0) continue;
          final lat = latOfRow(m.roi.v0 + j, canvasH);
          final lon = lonOfCol(m.roi.u0 + i, canvasW);
          final d = directionOf(lat, lon);
          final c = directionOf(centre.lat, centre.lon);
          final dot = d[0] * c[0] + d[1] * c[1] + d[2] * c[2];
          expect(dot, greaterThan(0), reason: 'linza orqasidagi piksel');
        }
      }
    });

    test('QUTB kadrida linza ORQASI kesiladi', () {
      // Bu `cz <= 1e-6` tekshiruvining YAGONA haqiqiy ishlaydigan joyi.
      // Oddiy kadrda iz — markaz atrofidagi ~38° qalpoq, ya'ni linza
      // orqasidagi yo'nalish izga UMUMAN tushmaydi va kadr chegarasi
      // tekshiruvi yetadi. Qutb kadrida esa iz tuvalning BUTUN enini
      // egallaydi (`halfLon = π`), ya'ni izda kameraning orqasidagi
      // yo'nalishlar ham bor — ular kesilmasa kadr sferaning teskari
      // tomoniga «arvoh» bo'lib tushardi.
      final r = rotationMatrix(0, math.pi / 2, 0);
      final m = buildFrameMap(
        rotation: r,
        frameW: fw,
        frameH: fh,
        focal: focal,
        canvasW: canvasW,
        canvasH: canvasH,
      );
      expect(m.roi.width, canvasW, reason: 'qutb izi to‘liq enli');
      final centre = frameCentre(r);
      final c = directionOf(centre.lat, centre.lon);
      var behind = 0;
      for (int j = 0; j < m.roi.height; j++) {
        for (int i = 0; i < m.roi.width; i++) {
          if (m.valid[j * m.roi.width + i] == 0) continue;
          final d = directionOf(
            latOfRow(m.roi.v0 + j, canvasH),
            lonOfCol(m.roi.u0 + i, canvasW),
          );
          if (d[0] * c[0] + d[1] * c[1] + d[2] * c[2] <= 0) behind++;
        }
      }
      expect(behind, 0, reason: 'linza orqasidan namuna olinmasligi kerak');
    });

    test('JUDA KENG FOV: linza orqasi kesiladi', () {
      // `cz <= 1e-6` tekshiruvining haqiqatan ishlaydigan sharoiti.
      //
      // Ikki shart kerak: (a) qalpoq radiusi katta bo'lsin (170° FOV →
      // ~87.6°) va (b) kadr QIYA bo'lsin, ya'ni `|lat| + radius >= 90`
      // va iz butun aylanani egallasin. O'shanda izga kameraning
      // ORQASIDAGI yo'nalishlar ham tushadi. Kesilmasa kadr sferaning
      // teskari tomoniga «arvoh» bo'lib qo'yilardi.
      //
      // Bizning haqiqiy FOV'imizda (67.3°) bu holat YUZAGA KELMAYDI —
      // shuning uchun test sun'iy keng FOV ishlatadi.
      final wideFocal = focalPx(fw, fh, 170);
      final r = rotationMatrix(0, math.pi / 3, 0);
      final m = buildFrameMap(
        rotation: r,
        frameW: fw,
        frameH: fh,
        focal: wideFocal,
        canvasW: canvasW,
        canvasH: canvasH,
      );
      final centre = frameCentre(r);
      final c = directionOf(centre.lat, centre.lon);

      double dotAt(int j, int i) {
        final d = directionOf(
          latOfRow(m.roi.v0 + j, canvasH),
          lonOfCol(m.roi.u0 + i, canvasW),
        );
        return d[0] * c[0] + d[1] * c[1] + d[2] * c[2];
      }

      // SHART: iz orqa tomonni qamragan bo'lsin — aks holda test hech
      // nimani sinamagan bo'lardi.
      var roiCoversBack = 0;
      var behind = 0;
      for (int j = 0; j < m.roi.height; j++) {
        for (int i = 0; i < m.roi.width; i++) {
          if (dotAt(j, i) > 0) continue;
          roiCoversBack++;
          if (m.valid[j * m.roi.width + i] != 0) behind++;
        }
      }
      expect(roiCoversBack, greaterThan(100), reason: 'iz orqani qamrasin');
      expect(behind, 0, reason: 'orqadagi yo‘nalishdan namuna olinmasin');
    });

    test('og‘irlik MARKAZDA eng katta, chetda nolga intiladi', () {
      // Butun yondashuv shunga tayanadi: markazi eng yaqin kadr yutadi va
      // o'z o'tkirligini saqlaydi.
      final m = mapAt(0, 0);
      double best = -1;
      int bestIdx = -1;
      for (int i = 0; i < m.length; i++) {
        if (m.weight[i] > best) {
          best = m.weight[i];
          bestIdx = i;
        }
      }
      expect(best, closeTo(1, 0.05), reason: 'markazda ~1');
      // Eng og'ir piksel kadr markaziga tushishi kerak.
      expect(m.mapX[bestIdx], closeTo(fw / 2, 2));
      expect(m.mapY[bestIdx], closeTo(fh / 2, 2));
    });

    test('QOPLANGAN piksel og‘irligi hech qachon 0 emas', () {
      // Nol og'irlikli piksel qat'iy `>` bilan HECH KIM tomonidan
      // olinmaydi va qora qolib ketadi — keyin detal o'tishi uni QORA
      // SOCH TOLASI bo'lib panoramaga ko'taradi.
      final m = mapAt(0, 0);
      for (int i = 0; i < m.length; i++) {
        if (m.valid[i] > 0) {
          expect(m.weight[i], greaterThanOrEqualTo(kCoveredFloor));
        }
      }
    });

    test('winnerTakeAll og‘irligi LINEAR, o‘rtachalash rejimi TIK', () {
      final wta = mapAt(0, 0, wta: true);
      final avg = mapAt(0, 0, wta: false);
      // Bir xil geometriya — bir xil iz va bir xil `valid`.
      expect(avg.roi.width, wta.roi.width);
      expect(avg.valid, wta.valid);
      // Chetga yaqin pikselda tik og'irlik ANCHA kichik.
      var found = false;
      for (int i = 0; i < wta.length; i++) {
        if (wta.valid[i] > 0 && wta.weight[i] > 0.2 && wta.weight[i] < 0.5) {
          expect(avg.weight[i], lessThan(wta.weight[i] / 100));
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'oraliq og‘irlikli piksel topilmadi');
    });

    test('blendPower 16 → t^16', () {
      final m = buildFrameMap(
        rotation: rotationMatrix(0, 0, 0),
        frameW: fw,
        frameH: fh,
        focal: focal,
        canvasW: canvasW,
        canvasH: canvasH,
        blendPower: 16,
        winnerTakeAll: false,
      );
      final lin = mapAt(0, 0);
      for (int i = 0; i < m.length; i++) {
        // Og'irligi 0.6 dan katta piksel: `0.6^16 = 2.8e-13`... yo'q,
        // aksincha — pol 1e-8, ya'ni `t^16 > 1e-8` uchun `t > 0.316`
        // kerak. 0.6 zaxira bilan oshadi.
        if (m.valid[i] > 0 && lin.weight[i] > 0.6) {
          final want = math.pow(lin.weight[i], 16) as double;
          expect(want, greaterThan(kCoveredFloor), reason: 'pol tegmasin');
          expect(m.weight[i] / want, closeTo(1, 1e-4));
          return;
        }
      }
      fail('mos piksel topilmadi');
    });
  });

  group('aylanma yo‘l — sfera → kadr → tuval', () {
    /// Sun'iy sfera: har yo'nalishga takrorlanmaydigan kulrang qiymat.
    int sphereValue(double lat, double lon) {
      final a = ((lon % (2 * math.pi)) / (2 * math.pi) * 13).floor();
      final b = ((lat + math.pi / 2) / math.pi * 7).floor();
      return 30 + ((a * 7 + b * 13) % 200);
    }

    /// Sferadan kadr «suratga olish» — proyeksiyaning TESKARISI.
    Uint8List shoot(List<double> r) {
      final out = Uint8List(fw * fh);
      final cx = fw / 2, cy = fh / 2;
      for (int y = 0; y < fh; y++) {
        for (int x = 0; x < fw; x++) {
          final v = cameraRayFromPixel(x + 0.0, y + 0.0, cx, cy, focal);
          // Kamera → dunyo (matritsaning O'ZI, transpozi emas).
          final wx = r[0] * v[0] + r[1] * v[1] + r[2] * v[2];
          final wy = r[3] * v[0] + r[4] * v[1] + r[5] * v[2];
          final wz = r[6] * v[0] + r[7] * v[1] + r[8] * v[2];
          final lat = math.asin(wy.clamp(-1.0, 1.0));
          final lon = math.atan2(wx, wz);
          out[y * fw + x] = sphereValue(lat, lon);
        }
      }
      return out;
    }

    test('bitta kadr o‘z izida sferani QAYTA TIKLAYDI', () {
      // To'rt kelishuvni bir vaqtda tekshiradigan test. Biri buzilsa
      // (ishora, transpoz, yarim piksel, o'q tartibi) mos kelmaydi.
      final r = rotationMatrix(0.5, 0.2, 0);
      final frame = shoot(r);
      final map = buildFrameMap(
        rotation: r,
        frameW: fw,
        frameH: fh,
        focal: focal,
        canvasW: canvasW,
        canvasH: canvasH,
      );
      final canvas = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      compositeFrame(canvas, map, <Uint8List>[frame], fw, fh, 0);

      var checked = 0;
      var wrong = 0;
      for (int y = 0; y < canvasH; y++) {
        for (int x = 0; x < canvasW; x++) {
          final d = y * canvasW + x;
          // Faqat ISHONCHLI qoplangan piksellar: kadr chekkasida
          // bilinear namuna qo'shni katakdan aralashadi.
          if (canvas.weight[d] < 0.25) continue;
          checked++;
          final want = sphereValue(latOfRow(y, canvasH), lonOfCol(x, canvasW));
          if ((canvas.color[d] - want).abs() > 1) wrong++;
        }
      }
      expect(checked, greaterThan(500), reason: 'yetarli piksel tekshirilsin');
      // Katak chegaralari bilinear namunada aralashadi — 6 % gacha yo'l
      // qo'yiladi. Kelishuvlardan biri buzilsa bu 50 % dan oshadi.
      expect(wrong / checked, lessThan(0.06));
    });

    test('kelishuv BUZILSA aylanma yo‘l yopilmaydi', () {
      // Yuqoridagi testning sezgirligini isbotlaydi: matritsa
      // transpozini almashtirsak mos kelmaslik keskin oshadi.
      final r = rotationMatrix(0.5, 0.2, 0);
      final frame = shoot(r);
      final wrongR = <double>[
        r[0], r[3], r[6],
        r[1], r[4], r[7],
        r[2], r[5], r[8],
      ];
      final map = buildFrameMap(
        rotation: wrongR,
        frameW: fw,
        frameH: fh,
        focal: focal,
        canvasW: canvasW,
        canvasH: canvasH,
      );
      final canvas = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      compositeFrame(canvas, map, <Uint8List>[frame], fw, fh, 0);
      var checked = 0, wrong = 0;
      for (int y = 0; y < canvasH; y++) {
        for (int x = 0; x < canvasW; x++) {
          final d = y * canvasW + x;
          if (canvas.weight[d] < 0.25) continue;
          checked++;
          final want = sphereValue(latOfRow(y, canvasH), lonOfCol(x, canvasW));
          if ((canvas.color[d] - want).abs() > 1) wrong++;
        }
      }
      expect(wrong / checked, greaterThan(0.3), reason: 'test sezgir bo‘lsin');
    });
  });

  group('compositeFrame — winner-take-all', () {
    Uint8List flat(int v) => Uint8List(fw * fh)..fillRange(0, fw * fh, v);

    test('bo‘sh tuvalda kadr o‘z izini egallaydi', () {
      final canvas = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      final m = mapAt(0, 0);
      compositeFrame(canvas, m, <Uint8List>[flat(100)], fw, fh, 7);
      final claimed = canvas.label!.where((l) => l == 7).length;
      expect(claimed, greaterThan(0));
      expect(canvas.label!.where((l) => l == -1).length, canvas.pixels - claimed);
    });

    test('OG‘IRROQ kadr yutadi, tartibdan qat’i nazar', () {
      // Ikki kadr: biri markazga, ikkinchisi yonga qaragan. Ustma-ust
      // tushgan joyda markazi yaqinroq bo'lgani yutishi kerak — va bu
      // qaysi biri OLDIN qo'yilganiga bog'liq BO'LMASLIGI kerak.
      List<int> run(bool aFirst) {
        final c = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
        final a = mapAt(0, 0);
        final b = mapAt(0.5, 0);
        if (aFirst) {
          compositeFrame(c, a, <Uint8List>[flat(50)], fw, fh, 1);
          compositeFrame(c, b, <Uint8List>[flat(200)], fw, fh, 2);
        } else {
          compositeFrame(c, b, <Uint8List>[flat(200)], fw, fh, 2);
          compositeFrame(c, a, <Uint8List>[flat(50)], fw, fh, 1);
        }
        return c.label!.toList();
      }
      expect(run(true), run(false));
    });

    test('QAT‘IY `>` — teng og‘irlikda BIRINCHI kadr qoladi', () {
      // `>=` bo'lsa oxirgi kadr yutardi va natija tartibga bog'liq
      // bo'lardi (yuqoridagi test aynan shuni ushlaydi).
      final c = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      final m = mapAt(0, 0);
      compositeFrame(c, m, <Uint8List>[flat(50)], fw, fh, 1);
      compositeFrame(c, m, <Uint8List>[flat(200)], fw, fh, 2);
      expect(c.label!.where((l) => l == 2), isEmpty);
      expect(c.label!.where((l) => l == 1), isNotEmpty);
    });

    test('gain rangga qo‘llanadi', () {
      final c = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      compositeFrame(c, mapAt(0, 0), <Uint8List>[flat(100)], fw, fh, 0, gain: 1.5);
      final vals = <double>[];
      for (int i = 0; i < c.pixels; i++) {
        if (c.label![i] == 0) vals.add(c.color[i]);
      }
      expect(vals, isNotEmpty);
      expect(vals.every((v) => (v - 150).abs() < 1.5), isTrue);
    });

    test('cover og‘irlikdan ALOHIDA sanaladi', () {
      final c = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      final m = mapAt(0, 0);
      compositeFrame(c, m, <Uint8List>[flat(100)], fw, fh, 0);
      final covered = c.cover.where((v) => v > 0).length;
      expect(covered, m.valid.where((v) => v > 0).length);
      // Ikkinchi kadr cover'ni QO'SHADI, hatto yutmasa ham.
      compositeFrame(c, m, <Uint8List>[flat(100)], fw, fh, 1);
      expect(c.cover.reduce(math.max), 2);
    });

    test('O‘RALGAN kadr tuvalning IKKI chetiga ham yozadi', () {
      // Chokka qaragan kadr — `columnBlocks` shu yerda ishlaydi. O'rash
      // bo'lmasa kadr yarmiga bo'linardi va u yerda doimiy vertikal
      // chiziq qolardi.
      final c = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      final m = mapAt(0, 0); // lon = 0 → iz manfiy u0 dan boshlanadi
      expect(m.roi.u0, lessThan(0), reason: 'chokni kesib o‘tsin');
      compositeFrame(c, m, <Uint8List>[flat(120)], fw, fh, 3);
      final row = canvasH ~/ 2;
      expect(c.label![row * canvasW + 0], 3, reason: 'chap chet');
      expect(c.label![row * canvasW + canvasW - 1], 3, reason: 'o‘ng chet');
    });
  });

  group('compositeFrame — o‘rtachalash rejimi', () {
    /// ⚠️ O'rtachalash rejimi `blendPower: 1` bilan ishlatiladi — manbada
    /// ham shunday (`_grayCanvas`). Sabab keyingi testda.
    FrameMap avgMap(double psi, double theta) => buildFrameMap(
      rotation: rotationMatrix(psi, theta, 0),
      frameW: fw,
      frameH: fh,
      focal: focal,
      canvasW: canvasW,
      canvasH: canvasH,
      blendPower: 1,
      winnerTakeAll: false,
    );

    test('ikki kadr O‘RTACHALANADI', () {
      final c = PanoCanvas(
        width: canvasW,
        height: canvasH,
        channels: 1,
        withLabel: false,
      );
      final m = avgMap(0, 0);
      final a = Uint8List(fw * fh)..fillRange(0, fw * fh, 60);
      final b = Uint8List(fw * fh)..fillRange(0, fw * fh, 180);
      compositeFrame(c, m, <Uint8List>[a], fw, fh, 0, winnerTakeAll: false);
      compositeFrame(c, m, <Uint8List>[b], fw, fh, 1, winnerTakeAll: false);
      final out = resolveCanvas(c, winnerTakeAll: false);
      // Bir xil og'irlik — aniq o'rtacha.
      // Og'irligi `eps` (1e-6) bilan solishtirsa bo'ladigan darajada
      // kichik piksellar CHIQARIB TASHLANADI — ular kadrning aynan
      // chekkasida va keyingi test ularga bag'ishlangan.
      final covered = <int>[
        for (int i = 0; i < c.pixels; i++)
          if (c.cover[i] > 0 && c.weight[i] > 1e-3) out[i],
      ];
      expect(covered, hasLength(greaterThan(1000)));
      expect(covered.every((v) => (v - 120).abs() <= 1), isTrue);
    });

    test('TIK og‘irlik o‘rtachalash bilan MOS KELMAYDI — shuning uchun 1',
        () {
      // `blendPower: 16` da kadr chekkasidagi og'irlik `kCoveredFloor`
      // (1e-8) ga tushadi, `divideSafe` ning `eps` i esa 1e-6 — ya'ni
      // maxrajni butunlay egallaydi va o'sha piksellar qorayadi.
      // Manba shu sababli o'rtachalash yo'lida HAR DOIM `blendPower: 1`
      // beradi. Bu test kombinatsiyaning yomonligini QOTIRADI, toki
      // kelajakda kimdir uni «yaxshilash» uchun 16 qilib qo'ymasin.
      PanoCanvas run(int power) {
        final c = PanoCanvas(
          width: canvasW,
          height: canvasH,
          channels: 1,
          withLabel: false,
        );
        final m = buildFrameMap(
          rotation: rotationMatrix(0, 0, 0),
          frameW: fw,
          frameH: fh,
          focal: focal,
          canvasW: canvasW,
          canvasH: canvasH,
          blendPower: power,
          winnerTakeAll: false,
        );
        final f = Uint8List(fw * fh)..fillRange(0, fw * fh, 120);
        compositeFrame(c, m, <Uint8List>[f], fw, fh, 0, winnerTakeAll: false);
        return c;
      }

      int rimDark(PanoCanvas c) {
        final out = resolveCanvas(c, winnerTakeAll: false);
        var n = 0;
        for (var i = 0; i < c.pixels; i++) {
          if (c.cover[i] > 0 && out[i] < 100) n++;
        }
        return n;
      }

      // O'lchangan (64×64 kadr, 256×128 tuval, 1704 qoplangan piksel):
      // linear og'irlikda 2 piksel qorayadi (0.1 % — kadrning aynan
      // chekkasi), tik og'irlikda 1328 (78 %).
      final one = run(1);
      final sixteen = run(16);
      final int coveredCount = one.cover.where((v) => v > 0).length;
      expect(rimDark(one) / coveredCount, lessThan(0.01));
      expect(rimDark(sixteen) / coveredCount, greaterThan(0.5));
    });

    test('QOPLANMAGAN piksel qora — NaN emas', () {
      // `0/0` Dart'da NaN va NaN keyingi hamma amalga yuqadi.
      final c = PanoCanvas(
        width: canvasW,
        height: canvasH,
        channels: 1,
        withLabel: false,
      );
      final out = resolveCanvas(c, winnerTakeAll: false);
      expect(out.every((v) => v == 0), isTrue);
    });

    test('label yo‘q bo‘lsa yiqilmaydi', () {
      final c = PanoCanvas(
        width: canvasW,
        height: canvasH,
        channels: 1,
        withLabel: false,
      );
      expect(c.label, isNull);
      compositeFrame(
        c,
        avgMap(0, 0),
        <Uint8List>[Uint8List(fw * fh)],
        fw,
        fh,
        0,
      );
      expect(c.weight.any((w) => w > 0), isTrue);
    });
  });

  group('rowCoverage', () {
    test('qamralgan qator 255·piksel beradi', () {
      final c = PanoCanvas(width: 4, height: 2, channels: 1);
      c.cover[0] = 1;
      c.cover[1] = 1;
      c.cover[4] = 3;
      final rows = rowCoverage(c);
      expect(rows, <int>[2 * 255, 1 * 255]);
    });

    test('og‘irlik emas, COVER o‘qiladi', () {
      // Og'irlik `kCoveredFloor` ga tushishi mumkin, lekin piksel
      // baribir qoplangan — qamrov shundan sanalmasligi kerak.
      final c = PanoCanvas(width: 2, height: 1, channels: 1);
      c.cover[0] = 1;
      c.weight[0] = kCoveredFloor;
      expect(rowCoverage(c), <int>[255]);
    });
  });

  group('horizontalSlices — isolate bo‘laklari', () {
    test('tuvalni TO‘LIQ va kesishmasdan qoplaydi', () {
      for (final h in <int>[1, 2, 7, 128, 1536]) {
        for (final w in <int>[1, 2, 3, 4, 8]) {
          final s = horizontalSlices(h, w);
          expect(s.fold<int>(0, (a, x) => a + x.$2), h, reason: 'h=$h w=$w');
          for (int i = 1; i < s.length; i++) {
            expect(s[i].$1, s[i - 1].$1 + s[i - 1].$2, reason: 'h=$h w=$w');
          }
          expect(s.first.$1, 0);
        }
      }
    });

    test('tasmalar farqi ENG KO‘PI bitta qator', () {
      final s = horizontalSlices(1536, 7);
      final sizes = s.map((x) => x.$2).toList();
      expect(sizes.reduce(math.max) - sizes.reduce(math.min), lessThanOrEqualTo(1));
    });

    test('ishchi qatordan ko‘p bo‘lsa bo‘sh tasma chiqmaydi', () {
      final s = horizontalSlices(3, 10);
      expect(s, hasLength(3));
      expect(s.every((x) => x.$2 > 0), isTrue);
    });

    test('roiIntersectsRows kesishmani to‘g‘ri aytadi', () {
      const roi = Roi(0, 100, 10, 50); // qatorlar 100..149
      expect(roiIntersectsRows(roi, 0, 100), isFalse, reason: 'aynan tegmaydi');
      expect(roiIntersectsRows(roi, 0, 101), isTrue);
      expect(roiIntersectsRows(roi, 150, 10), isFalse);
      expect(roiIntersectsRows(roi, 149, 10), isTrue);
      expect(roiIntersectsRows(roi, 120, 5), isTrue, reason: 'ichida');
      expect(roiIntersectsRows(const Roi(0, 0, 0, 0), 0, 100), isFalse);
    });

    test('TASMALARGA bo‘lib qo‘yish YAXLIT natija bilan bir xil', () {
      // Isolate parallelligi natijani o'zgartirmasligi SHART.
      final m = mapAt(0.3, 0.1);
      final frame = Uint8List(fw * fh);
      for (int i = 0; i < frame.length; i++) {
        frame[i] = (i * 37) % 256;
      }

      final whole = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      compositeFrame(whole, m, <Uint8List>[frame], fw, fh, 5);

      final sliced = PanoCanvas(width: canvasW, height: canvasH, channels: 1);
      for (final (v0, rows) in horizontalSlices(canvasH, 4)) {
        if (!roiIntersectsRows(m.roi, v0, rows)) continue;
        compositeFrame(
          sliced,
          m,
          <Uint8List>[frame],
          fw,
          fh,
          5,
          rowFrom: v0,
          rowTo: v0 + rows,
        );
      }
      expect(sliced.label, whole.label);
      expect(sliced.color, whole.color);
      expect(sliced.weight, whole.weight);
      expect(sliced.cover, whole.cover);
    });

    test('kesishmagan tasmalar O‘TKAZIB YUBORILADI', () {
      // Gorizont kadri 1536 qatorli tuvalning atigi yarmini qamraydi.
      final m = buildFrameMap(
        rotation: rotationMatrix(0, 0, 0),
        frameW: fw,
        frameH: fh,
        focal: focal,
        canvasW: 3072,
        canvasH: 1536,
      );
      final skipped = horizontalSlices(1536, 4)
          .where((s) => !roiIntersectsRows(m.roi, s.$1, s.$2))
          .length;
      expect(skipped, greaterThan(0), reason: 'ba’zi tasmalar tegmaydi');
    });
  });
}
